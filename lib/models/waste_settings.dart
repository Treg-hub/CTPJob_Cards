import 'package:cloud_firestore/cloud_firestore.dart';

/// Global WasteTrack configuration stored in waste_settings/config.
/// Mirrors the FleetSettings pattern exactly.
class WasteSettings {
  final List<String> managerClockNos;
  final List<String> guardClockNos;
  final bool wasteEnabled;

  const WasteSettings({
    this.managerClockNos = const [],
    this.guardClockNos = const [],
    this.wasteEnabled = true,
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'manager_clock_nos': managerClockNos,
      'guard_clock_nos': guardClockNos,
      'waste_enabled': wasteEnabled,
    };
  }

  WasteSettings copyWith({
    List<String>? managerClockNos,
    List<String>? guardClockNos,
    bool? wasteEnabled,
  }) {
    return WasteSettings(
      managerClockNos: managerClockNos ?? this.managerClockNos,
      guardClockNos: guardClockNos ?? this.guardClockNos,
      wasteEnabled: wasteEnabled ?? this.wasteEnabled,
    );
  }
}
