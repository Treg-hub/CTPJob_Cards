import 'package:cloud_firestore/cloud_firestore.dart';

/// Master waste type definition (waste_types collection).
/// Defines the main type + its allowed subtypes + how quantity should be labeled in the UI.
class WasteType {
  final String? id;
  final String mainType;
  final List<String> subtypes;
  final Map<String, String> quantityLabels; // subtype -> label, e.g. "Reelends" -> "Quantity (reels)"
  /// True for types measured by count, not weight (e.g. IBC Bins).
  /// Weight field is hidden; quantity is required. Weighbridge step is skipped.
  final bool isQuantityOnly;

  /// True for types too large to weigh on-site (e.g. compactor bins, copper skins).
  /// Guard records quantity; weight field is hidden. Weighbridge step is still required.
  final bool noSiteWeight;

  const WasteType({
    this.id,
    required this.mainType,
    this.subtypes = const [],
    this.quantityLabels = const {},
    this.isQuantityOnly = false,
    this.noSiteWeight = false,
  });

  /// Returns the dynamic quantity label for a given subtype.
  /// For quantity-only types, returns the 'default' label or "Quantity (units)".
  String quantityLabelFor(String subtype) {
    return quantityLabels[subtype] ?? quantityLabels['default'] ?? 'Quantity (units)';
  }

  factory WasteType.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WasteType(
      id: doc.id,
      mainType: data['mainType'] as String? ?? data['main_type'] as String? ?? '',
      subtypes: (data['subtypes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      quantityLabels: (data['quantityLabels'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      isQuantityOnly: data['isQuantityOnly'] as bool? ?? false,
      noSiteWeight: data['noSiteWeight'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'mainType': mainType,
        'subtypes': subtypes,
        'quantityLabels': quantityLabels,
        'isQuantityOnly': isQuantityOnly,
        'noSiteWeight': noSiteWeight,
      };
}
