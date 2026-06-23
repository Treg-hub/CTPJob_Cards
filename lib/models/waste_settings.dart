import 'package:cloud_firestore/cloud_firestore.dart';

/// Global WasteTrack configuration stored in waste_settings/config.
class WasteSettings {
  final List<String> managerClockNos;
  final List<String> guardClockNos;
  final bool wasteEnabled;
  final bool photosRequired;
  final bool signatureRequired;

  const WasteSettings({
    this.managerClockNos = const [],
    this.guardClockNos = const [],
    this.wasteEnabled = true,
    this.photosRequired = false,
    this.signatureRequired = false,
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
      photosRequired: data['photos_required'] as bool? ?? false,
      signatureRequired: data['signature_required'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'manager_clock_nos': managerClockNos,
      'guard_clock_nos': guardClockNos,
      'waste_enabled': wasteEnabled,
      'photos_required': photosRequired,
      'signature_required': signatureRequired,
    };
  }

  WasteSettings copyWith({
    List<String>? managerClockNos,
    List<String>? guardClockNos,
    bool? wasteEnabled,
    bool? photosRequired,
    bool? signatureRequired,
  }) {
    return WasteSettings(
      managerClockNos: managerClockNos ?? this.managerClockNos,
      guardClockNos: guardClockNos ?? this.guardClockNos,
      wasteEnabled: wasteEnabled ?? this.wasteEnabled,
      photosRequired: photosRequired ?? this.photosRequired,
      signatureRequired: signatureRequired ?? this.signatureRequired,
    );
  }
}