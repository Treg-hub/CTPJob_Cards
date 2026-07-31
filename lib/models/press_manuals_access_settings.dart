/// Access flags for Press Manuals (`settings/press_manuals_access`).
///
/// **isAdmin always has access** (not stored here). These switches and the
/// allowlist open the library to additional people when an admin configures
/// them.
class PressManualsAccessSettings {
  /// Department == Pressroom (operators, managers, techs in that dept).
  final bool allowPressroom;

  /// Inferred technician role (mechanic / electrical / technician, etc.),
  /// any department — same basis as [roleFromEmployee] → technician.
  final bool allowTechnicians;

  /// Explicit clock numbers granted access regardless of department/role
  /// toggles (managers outside Pressroom, named operators, etc.).
  final List<String> allowedClockNos;

  const PressManualsAccessSettings({
    this.allowPressroom = false,
    this.allowTechnicians = false,
    this.allowedClockNos = const [],
  });

  static const defaults = PressManualsAccessSettings();

  static List<String> _parseClockNos(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      out.add(s);
    }
    out.sort();
    return out;
  }

  factory PressManualsAccessSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return PressManualsAccessSettings(
      allowPressroom: data['allow_pressroom'] == true,
      allowTechnicians: data['allow_technicians'] == true,
      allowedClockNos: _parseClockNos(data['allowed_clock_nos']),
    );
  }

  Map<String, dynamic> toMap() => {
        'allow_pressroom': allowPressroom,
        'allow_technicians': allowTechnicians,
        'allowed_clock_nos': allowedClockNos,
      };

  /// True when [clockNo] is on the explicit allowlist.
  bool isClockAllowed(String? clockNo) {
    if (clockNo == null) return false;
    final c = clockNo.trim();
    if (c.isEmpty) return false;
    return allowedClockNos.contains(c);
  }

  PressManualsAccessSettings copyWith({
    bool? allowPressroom,
    bool? allowTechnicians,
    List<String>? allowedClockNos,
  }) {
    return PressManualsAccessSettings(
      allowPressroom: allowPressroom ?? this.allowPressroom,
      allowTechnicians: allowTechnicians ?? this.allowTechnicians,
      allowedClockNos: allowedClockNos ?? this.allowedClockNos,
    );
  }
}
