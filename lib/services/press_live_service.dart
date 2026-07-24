import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../utils/role.dart' as role_utils;

/// Access + snapshot helpers for Press Live (`press_live/current`).
class PressLiveService {
  PressLiveService._();
  static final PressLiveService instance = PressLiveService._();

  static const accessDoc = 'settings/press_live_access';
  static const snapshotDoc = 'press_live/current';

  List<String>? _cachedClockNos;
  DateTime? _cacheAt;

  void invalidateAccessCache() {
    _cachedClockNos = null;
    _cacheAt = null;
  }

  Future<List<String>> _loadClockNos({bool force = false}) async {
    if (!force &&
        _cachedClockNos != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < const Duration(minutes: 5)) {
      return _cachedClockNos!;
    }
    final snap = await FirebaseFirestore.instance.doc(accessDoc).get();
    final raw = snap.data()?['clock_nos'];
    final list = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) list.add(s);
      }
    }
    _cachedClockNos = list;
    _cacheAt = DateTime.now();
    return list;
  }

  /// Admins always; others must appear in [settings/press_live_access].clock_nos.
  Future<bool> canViewPressLive(Employee? employee) async {
    if (employee == null) return false;
    if (role_utils.isAdmin(employee)) return true;
    final clocks = await _loadClockNos();
    return clocks.contains(employee.clockNo.trim());
  }
}
