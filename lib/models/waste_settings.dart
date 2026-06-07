import 'package:cloud_firestore/cloud_firestore.dart';

/// Global WasteTrack configuration stored in waste_settings/config.
/// Mirrors the FleetSettings pattern exactly.
class WasteSettings {
  final List<String> managerClockNos;
  final List<String> guardClockNos;
  final bool wasteEnabled;

  /// When true, security guards can schedule an incoming load before the
  /// contractor arrives — not just begin collections. Controlled from
  /// CTP Pulse Waste Settings → Module → "Guards Can Schedule Loads".
  final bool guardCanSchedule;

  const WasteSettings({
    this.managerClockNos = const [],
    this.guardClockNos = const [],
    this.wasteEnabled = true,
    this.guardCanSchedule = false,
  });

  static const WasteSettings defaults = WasteSettings();

  factory WasteSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WasteSettings(
      managerClockNos: (data['manager_clock_nos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      guardClockNos: (data['guard_clock_nos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      wasteEnabled: data['waste_enabled'] as bool? ?? true,
      guardCanSchedule: data['guard_can_schedule'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'manager_clock_nos': managerClockNos,
      'guard_clock_nos': guardClockNos,
      'waste_enabled': wasteEnabled,
      'guard_can_schedule': guardCanSchedule,
    };
  }

  WasteSettings copyWith({
    List<String>? managerClockNos,
    List<String>? guardClockNos,
    bool? wasteEnabled,
    bool? guardCanSchedule,
  }) {
    return WasteSettings(
      managerClockNos: managerClockNos ?? this.managerClockNos,
      guardClockNos: guardClockNos ?? this.guardClockNos,
      wasteEnabled: wasteEnabled ?? this.wasteEnabled,
      guardCanSchedule: guardCanSchedule ?? this.guardCanSchedule,
    );
  }
}
