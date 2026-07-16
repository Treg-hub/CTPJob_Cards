import 'package:firebase_auth/firebase_auth.dart';

import '../services/module_claims.dart';

/// True when the signed-in Firebase user is a registry admin (`admins/{uid}`).
///
/// Prefers [ModuleClaims.isAdmin] after [AuthClaimsService] refresh (Phase 9);
/// falls back to a live token read. Used for persona picker gate.
Future<bool> isRegistryAdmin() async {
  final cached = ModuleClaims.instance.isAdmin;
  if (cached == true) return true;
  if (cached == false) return false;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final result = await user.getIdTokenResult();
    return result.claims?['isAdmin'] == true;
  } catch (_) {
    return false;
  }
}