import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'module_claims.dart';

/// Refreshes the signed-in user's Firebase custom claims (role, department,
/// isAdmin, Phase-1 module flags) by calling the server `setCustomClaims`
/// callable, then force-refreshing the local ID token so Firestore rules see
/// the new claims at once.
///
/// SECURITY: `isAdmin` is derived SERVER-SIDE from the locked `admins/{uid}`
/// collection — the client cannot grant itself admin. This call is what lets a
/// legitimately-seeded admin write the admin-only config collections
/// (`settings/app`, `settings/geofence`, `structures`, `notification_configs`)
/// once those rules require `isAdmin()`.
///
/// Always NON-FATAL: any failure (offline, cold start, no employee profile) is
/// swallowed so it can never block login or app startup.
///
/// Cost discipline: warm resume / hydrate skips the callable when a successful
/// refresh happened within [_ttl] and the local token already has `clockNum`.
/// Login, registration, permission-denied recovery, and manual Retry always
/// pass [force] so role/admin changes still land promptly when needed.
class AuthClaimsService {
  /// In-flight dedupe: several dead streams recovering at once must trigger
  /// ONE callable invocation, not one each.
  static Future<void>? _inFlight;

  static DateTime? _lastSuccessAt;

  /// Resume/hydrate TTL — long enough to cut Cloud Run spam, short enough that
  /// Pulse role / module-flag edits land within a factory half-shift without
  /// requiring re-login. Forced callers bypass this.
  static const Duration _ttl = Duration(minutes: 45);

  static final StreamController<bool> _completed =
      StreamController<bool>.broadcast();

  /// Emits after every [refreshClaims] attempt: true on success, false on
  /// failure. resilient_stream.dart uses the success events to resurrect
  /// streams that died on permission-denied while claims were being minted.
  static Stream<bool> get onRefreshCompleted => _completed.stream;

  /// [force] = always call `setCustomClaims` (login, registration, stream
  /// recovery, manual Retry, post-APK bootstrap). Default skips within [_ttl].
  static Future<void> refreshClaims({bool force = false}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _doRefresh(force: force);
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  static Future<void> _doRefresh({required bool force}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ModuleClaims.instance.clear();
      _lastSuccessAt = null;
      return;
    }
    try {
      if (!force && await _shouldSkipCallable(user)) {
        final token = await user.getIdTokenResult(false);
        final claims = Map<String, dynamic>.from(token.claims ?? const {});
        ModuleClaims.instance.applyFromTokenClaims(claims);
        debugPrint(
          'Custom claims TTL skip '
          '(age=${DateTime.now().difference(_lastSuccessAt!).inMinutes}m)',
        );
        _completed.add(true);
        return;
      }

      await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('setCustomClaims')
          .call()
          .timeout(const Duration(seconds: 8));
      // Force a token refresh so the freshly-set claims land in the local token
      // now, instead of after the next natural (~1h) refresh.
      final token = await user.getIdTokenResult(true);
      final claims = Map<String, dynamic>.from(token.claims ?? const {});
      ModuleClaims.instance.applyFromTokenClaims(claims);
      _lastSuccessAt = DateTime.now();
      // Phase 9: keep SharedPreferences admin flag aligned with claim (cold start).
      if (claims.containsKey('isAdmin')) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('loggedInAdmin', claims['isAdmin'] == true);
        } catch (_) {
          /* prefs optional */
        }
      }
      // Phase 8.4: clockNum is required for notification_inbox/{clockNo}/items.
      // Refresh succeeded but missing clockNum → loud log (inbox would be empty).
      final clockNum = (claims['clockNum'] as String?)?.trim() ?? '';
      if (clockNum.isEmpty) {
        debugPrint(
          '⚠️ CLAIMS MISSING clockNum after setCustomClaims — '
          'notification inbox will not load until employee profile is linked.',
        );
        if (!kIsWeb) {
          unawaited(FirebaseCrashlytics.instance
              .setCustomKey('claims_clocknum_missing', '1'));
          unawaited(FirebaseCrashlytics.instance
              .setCustomKey('claims_refresh_last', 'ok_no_clocknum'));
        }
      } else if (!kIsWeb) {
        unawaited(FirebaseCrashlytics.instance
            .setCustomKey('claims_clocknum_missing', '0'));
        unawaited(FirebaseCrashlytics.instance
            .setCustomKey('claims_refresh_last', 'ok'));
      }
      debugPrint(
        '✅ Custom claims refreshed for ${user.uid} '
        '(isAdmin=${ModuleClaims.instance.isAdmin})',
      );
      _completed.add(true);
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'set_custom_claims_refresh', fatal: false);
        unawaited(FirebaseCrashlytics.instance.setCustomKey(
            'claims_refresh_last',
            'failed:${e is FirebaseFunctionsException ? e.code : e.runtimeType}'));
      }
      debugPrint('Custom claims refresh failed (non-fatal): $e');
      _completed.add(false);
    }
  }

  static Future<bool> _shouldSkipCallable(User user) async {
    if (_lastSuccessAt == null) return false;
    if (DateTime.now().difference(_lastSuccessAt!) >= _ttl) return false;
    try {
      final token = await user.getIdTokenResult(false);
      final clockNum = (token.claims?['clockNum'] as String?)?.trim() ?? '';
      return clockNum.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Test/helper: clear TTL so the next [refreshClaims] always hits the CF.
  static void debugResetTtl() {
    _lastSuccessAt = null;
  }
}
