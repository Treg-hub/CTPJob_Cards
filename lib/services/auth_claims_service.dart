import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Refreshes the signed-in user's Firebase custom claims (role, department,
/// isAdmin) by calling the server `setCustomClaims` callable, then force-
/// refreshing the local ID token so Firestore rules see the new claims at once.
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
  static Future<void> refreshClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('setCustomClaims')
          .call()
          .timeout(const Duration(seconds: 8));
      // Force a token refresh so the freshly-set claims land in the local token
      // now, instead of after the next natural (~1h) refresh.
      await user.getIdTokenResult(true);
      debugPrint('✅ Custom claims refreshed for ${user.uid}');
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'set_custom_claims_refresh', fatal: false);
      }
      debugPrint('Custom claims refresh failed (non-fatal): $e');
    }
  }
}
