import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/widgets.dart';

import '../utils/stream_retry_policy.dart';
import 'auth_claims_service.dart';
import 'connectivity_service.dart';

/// App-wide events that should wake parked/backing-off resilient streams:
/// connectivity restored, custom-claims refresh completed, app resumed,
/// user (re-)signed in. Lazily initialized on first use — always after
/// runApp, so it never adds startup work.
class RetryTriggers with WidgetsBindingObserver {
  RetryTriggers._() {
    ConnectivityService().connectivityStream.listen((results) {
      // Same predicate as SyncService._startListening.
      if (results.any((r) => r != ConnectivityResult.none)) {
        _emit('connectivity');
      }
    });
    AuthClaimsService.onRefreshCompleted.listen((ok) {
      if (ok) _emit('claims');
    });
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _emit('auth');
    });
    WidgetsBinding.instance.addObserver(this);
  }

  static RetryTriggers? _instance;
  static RetryTriggers get instance => _instance ??= RetryTriggers._();

  final StreamController<String> _events = StreamController<String>.broadcast();
  final StreamController<void> _authSuspect = StreamController<void>.broadcast();

  /// 'connectivity' | 'claims' | 'auth' | 'resume'.
  Stream<String> get events => _events.stream;

  /// Fired when repeated permission-denied failures suggest the SESSION
  /// itself is dead (not just a claims race) — the session banner listens
  /// and runs its revocation check.
  Stream<void> get authSuspectEvents => _authSuspect.stream;

  void _emit(String event) {
    if (!_events.isClosed) _events.add(event);
  }

  void flagAuthSuspect() {
    if (!_authSuspect.isClosed) _authSuspect.add(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _emit('resume');
  }
}

/// Wraps a Firestore snapshot stream so errors no longer kill it for the rest
/// of the session. Firestore terminates a listener PERMANENTLY on
/// permission-denied; at cold start the home streams race the claims/token
/// refresh, so one transient denial used to blank the home screen until a
/// force-restart.
///
/// Behavior:
/// - Errors are classified by [classifyStreamError] → timed backoff retries,
///   claims-refresh-then-retry, or parking until a [RetryTriggers] event.
/// - Errors are NOT forwarded downstream by default: consumers keep their
///   last data, and a stream that has never emitted keeps its StreamBuilder
///   in `waiting` (the "connecting" UI) instead of a false error/empty state.
/// - Each successful emission resets the attempt counter.
/// - After 3+ consecutive permission-denied failures the session banner is
///   nudged via [RetryTriggers.flagAuthSuspect] (the claims refresh clearly
///   didn't fix it — the session itself may be revoked).
Stream<T> resilientSnapshots<T>(
  Stream<T> Function() build, {
  required String debugName,
  bool forwardErrors = false,
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  StreamSubscription<String>? triggerSub;
  Timer? retryTimer;
  var attempt = 0;
  var consecutiveDenied = 0;
  var parkedUntilAuth = false;
  var reportedNonFatal = false;

  late void Function() subscribe;

  void scheduleRetry(Duration delay) {
    retryTimer?.cancel();
    retryTimer = Timer(delay, () {
      retryTimer = null;
      subscribe();
    });
  }

  void handleError(Object error, StackTrace stack) {
    sub?.cancel();
    sub = null;
    attempt++;
    final code = error is FirebaseException ? error.code : null;
    if (code == 'permission-denied') {
      consecutiveDenied++;
      if (consecutiveDenied >= 3) RetryTriggers.instance.flagAuthSuspect();
    } else {
      consecutiveDenied = 0;
    }

    debugPrint('⚠️ stream[$debugName] error #$attempt ($code): $error');
    if (!kIsWeb) {
      unawaited(FirebaseCrashlytics.instance
          .log('stream[$debugName] error #$attempt code=$code'));
      if (!reportedNonFatal) {
        reportedNonFatal = true;
        FirebaseCrashlytics.instance.recordError(error, stack,
            reason: 'resilient_stream_$debugName', fatal: false);
      }
    }
    if (forwardErrors) controller.addError(error, stack);

    switch (classifyStreamError(code: code, attempt: attempt)) {
      case StreamRetryAction.refreshClaimsThenRetry:
        // Deduped inside AuthClaimsService — N dead streams, one callable.
        AuthClaimsService.refreshClaims()
            .whenComplete(() => scheduleRetry(retryBackoff(attempt)));
      case StreamRetryAction.retryAfterBackoff:
        scheduleRetry(retryBackoff(attempt));
      case StreamRetryAction.parkUntilTrigger:
        // No timer — the trigger subscription below resurrects us.
        break;
      case StreamRetryAction.parkUntilAuth:
        parkedUntilAuth = true;
    }
  }

  subscribe = () {
    if (controller.isClosed) return;
    parkedUntilAuth = false;
    try {
      sub = build().listen(
        (data) {
          attempt = 0;
          consecutiveDenied = 0;
          if (!controller.isClosed) controller.add(data);
        },
        onError: handleError,
      );
    } catch (e, st) {
      // build() itself threw (e.g. plugin channel not ready) — same policy.
      handleError(e, st);
    }
  };

  controller = StreamController<T>(
    onListen: () {
      subscribe();
      triggerSub = RetryTriggers.instance.events.listen((event) {
        // Only act when the stream is actually down (dead sub, no timer).
        if (sub != null || retryTimer != null) return;
        if (parkedUntilAuth && event != 'auth') return;
        attempt = 0;
        debugPrint('🔄 stream[$debugName] resubscribing on $event');
        subscribe();
      });
    },
    onCancel: () {
      retryTimer?.cancel();
      triggerSub?.cancel();
      return sub?.cancel();
    },
  );

  return controller.stream;
}
