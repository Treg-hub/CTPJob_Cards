/// Access flags for Press Manuals (`settings/press_manuals_access`).
///
/// **isAdmin always has access** (not stored here). These switches only open
/// the library to additional groups when an admin turns them on.
class PressManualsAccessSettings {
  /// Department == Pressroom (operators, managers, techs in that dept).
  final bool allowPressroom;

  /// Inferred technician role (mechanic / electrical / technician, etc.),
  /// any department — same basis as [roleFromEmployee] → technician.
  final bool allowTechnicians;

  const PressManualsAccessSettings({
    this.allowPressroom = false,
    this.allowTechnicians = false,
  });

  static const defaults = PressManualsAccessSettings();

  factory PressManualsAccessSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return PressManualsAccessSettings(
      allowPressroom: data['allow_pressroom'] == true,
      allowTechnicians: data['allow_technicians'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'allow_pressroom': allowPressroom,
        'allow_technicians': allowTechnicians,
      };

  PressManualsAccessSettings copyWith({
    bool? allowPressroom,
    bool? allowTechnicians,
  }) {
    return PressManualsAccessSettings(
      allowPressroom: allowPressroom ?? this.allowPressroom,
      allowTechnicians: allowTechnicians ?? this.allowTechnicians,
    );
  }
}
