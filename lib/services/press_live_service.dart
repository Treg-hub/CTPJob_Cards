import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../models/press_live_access.dart';
import '../utils/role.dart' as role_utils;

/// Access + snapshot helpers for Press Live (`press_live/current`).
class PressLiveService {
  PressLiveService._();
  static final PressLiveService instance = PressLiveService._();

  static const accessDoc = 'settings/press_live_access';
  static const snapshotDoc = 'press_live/current';

  PressLiveAccess? _cachedAccess;
  DateTime? _cacheAt;

  void invalidateAccessCache() {
    _cachedAccess = null;
    _cacheAt = null;
  }

  Future<PressLiveAccess> _loadAccess({bool force = false}) async {
    if (!force &&
        _cachedAccess != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < const Duration(minutes: 5)) {
      return _cachedAccess!;
    }
    final snap = await FirebaseFirestore.instance.doc(accessDoc).get();
    final access = PressLiveAccess.fromMap(snap.data());
    _cachedAccess = access;
    _cacheAt = DateTime.now();
    return access;
  }

  /// Admins always. Others: clock, department, or position on
  /// [settings/press_live_access].
  Future<bool> canViewPressLive(Employee? employee) async {
    if (employee == null) return false;
    if (role_utils.isAdmin(employee)) return true;
    final access = await _loadAccess();
    return access.allows(
      clockNo: employee.clockNo,
      department: employee.department,
      position: employee.position,
    );
  }
}
