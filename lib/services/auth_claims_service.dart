import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

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
class AuthClaimsService {
  /// In-flight dedupe: several dead streams recovering at once must trigger
  /// ONE callable invocation, not one each.
  static Future<void>? _inFlight;

  static final StreamController<bool> _completed =
      StreamController<bool>.broadcast();

  /// Emits after every [refreshClaims] attempt: true on success, false on
  /// failure. resilient_stream.dart uses the success events to resurrect
  /// streams that died on permission-denied while claims were being minted.
  static Stream<bool> get onRefreshCompleted => _completed.stream;

  static Future<void> refreshClaims() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _doRefresh();
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  static Future<void> _doRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ModuleClaims.instance.clear();
      return;
    }
    try {
      await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('setCustomClaims')
          .call()
          .timeout(const Duration(seconds: 8));
      // Force a token refresh so the freshly-set claims land in the local token
      // now, instead of after the next natural (~1h) refresh.
      final token = await user.getIdTokenResult(true);
      final claims = Map<String, dynamic>.from(token.claims ?? const {});
      ModuleClaims.instance.applyFromTokenClaims(claims);
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
      debugPrint('✅ Custom claims refreshed for ${user.uid}');
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
}
