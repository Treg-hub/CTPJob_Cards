import 'package:firebase_auth/firebase_auth.dart';

/// True when the signed-in Firebase user has `isAdmin: true` in custom claims
/// (from locked `admins/{uid}` via setCustomClaims). Used for persona picker gate.
Future<bool> isRegistryAdmin() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final result = await user.getIdTokenResult();
    return result.claims?['isAdmin'] == true;
  } catch (_) {
    return false;
  }
}