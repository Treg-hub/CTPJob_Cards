/// Allowlist for who may open Press Live (`settings/press_live_access`).
///
/// Any match is enough: individual clock, whole department, or whole position.
/// Admins are granted in [PressLiveService.canViewPressLive], not here.
class PressLiveAccess {
  const PressLiveAccess({
    this.clockNos = const [],
    this.departments = const [],
    this.positions = const [],
  });

  final List<String> clockNos;
  final List<String> departments;
  final List<String> positions;

  factory PressLiveAccess.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const PressLiveAccess();
    return PressLiveAccess(
      clockNos: _stringList(data['clock_nos']),
      departments: _stringList(data['departments']),
      positions: _stringList(data['positions']),
    );
  }

  Map<String, List<String>> toFirestore() {
    final clocks = [...clockNos]..sort();
    final depts = [...departments]..sort();
    final posts = [...positions]..sort();
    return {
      'clock_nos': clocks,
      'departments': depts,
      'positions': posts,
    };
  }

  /// Client match is case-insensitive so roster casing vs token claims still works.
  /// Rules persist the exact roster strings and match token department/position.
  bool allows({
    required String clockNo,
    required String department,
    required String position,
  }) {
    if (_listHas(clockNos, clockNo)) return true;
    if (_listHas(departments, department)) return true;
    if (_listHas(positions, position)) return true;
    return false;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isEmpty) continue;
      final key = s.toLowerCase();
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  static bool _listHas(List<String> hay, String needle) {
    final n = needle.trim().toLowerCase();
    if (n.isEmpty) return false;
    for (final e in hay) {
      if (e.trim().toLowerCase() == n) return true;
    }
    return false;
  }
}
