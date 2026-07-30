import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/press_manuals_access_settings.dart';

/// Reads/writes `settings/press_manuals_access` (admin write via rules).
class PressManualsAccessService {
  PressManualsAccessService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const docPath = 'settings/press_manuals_access';

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.doc(docPath);

  Future<PressManualsAccessSettings> getSettings() async {
    final snap = await _ref.get();
    return PressManualsAccessSettings.fromMap(snap.data());
  }

  Stream<PressManualsAccessSettings> watchSettings() {
    return _ref.snapshots().map(
          (snap) => PressManualsAccessSettings.fromMap(snap.data()),
        );
  }

  /// Admin-only (Firestore rules). Creates the doc if missing.
  Future<void> saveSettings(PressManualsAccessSettings settings) async {
    await _ref.set(settings.toMap(), SetOptions(merge: true));
  }
}
