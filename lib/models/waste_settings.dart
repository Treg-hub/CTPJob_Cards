import 'package:cloud_firestore/cloud_firestore.dart';

/// Global WasteTrack configuration stored in waste_settings/config.
class WasteSettings {
  final List<String> managerClockNos;
  final List<String> guardClockNos;
  final bool wasteEnabled;
  final bool photosRequired;
  final bool signatureRequired;

  /// Fixed empty weight of Copper Skins Bin 1 (kg). Used at collection only.
  final double copperSkinsBin1TareKg;

  /// Fixed empty weight of Copper Skins Bin 2 (kg). Used at collection only.
  final double copperSkinsBin2TareKg;

  const WasteSettings({
    this.managerClockNos = const [],
    this.guardClockNos = const [],
    this.wasteEnabled = true,
    this.photosRequired = false,
    this.signatureRequired = false,
    this.copperSkinsBin1TareKg = 0,
    this.copperSkinsBin2TareKg = 0,
  });

  static const WasteSettings defaults = WasteSettings();

  /// True when both Copper Skins bin tares are configured (> 0).
  bool get copperSkinsTaresConfigured =>
      copperSkinsBin1TareKg > 0 && copperSkinsBin2TareKg > 0;

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
      copperSkinsBin1TareKg:
          (data['copper_skins_bin1_tare_kg'] as num?)?.toDouble() ?? 0,
      copperSkinsBin2TareKg:
          (data['copper_skins_bin2_tare_kg'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'manager_clock_nos': managerClockNos,
      'guard_clock_nos': guardClockNos,
      'waste_enabled': wasteEnabled,
      'photos_required': photosRequired,
      'signature_required': signatureRequired,
      'copper_skins_bin1_tare_kg': copperSkinsBin1TareKg,
      'copper_skins_bin2_tare_kg': copperSkinsBin2TareKg,
    };
  }

  WasteSettings copyWith({
    List<String>? managerClockNos,
    List<String>? guardClockNos,
    bool? wasteEnabled,
    bool? photosRequired,
    bool? signatureRequired,
    double? copperSkinsBin1TareKg,
    double? copperSkinsBin2TareKg,
  }) {
    return WasteSettings(
      managerClockNos: managerClockNos ?? this.managerClockNos,
      guardClockNos: guardClockNos ?? this.guardClockNos,
      wasteEnabled: wasteEnabled ?? this.wasteEnabled,
      photosRequired: photosRequired ?? this.photosRequired,
      signatureRequired: signatureRequired ?? this.signatureRequired,
      copperSkinsBin1TareKg:
          copperSkinsBin1TareKg ?? this.copperSkinsBin1TareKg,
      copperSkinsBin2TareKg:
          copperSkinsBin2TareKg ?? this.copperSkinsBin2TareKg,
    );
  }
}