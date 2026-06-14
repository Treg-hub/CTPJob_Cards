import 'package:cloud_firestore/cloud_firestore.dart';

/// Master waste type definition (waste_types collection).
/// Defines the main type + its allowed subtypes + how quantity should be labeled in the UI.
class WasteType {
  final String? id;
  final String mainType;
  final List<String> subtypes;
  final Map<String, String> quantityLabels; // subtype -> label, e.g. "Reelends" -> "Quantity (reels)"
  /// True for types measured by count, not weight (e.g. IBC Bins).
  /// Weight field is hidden in all item entry screens; quantity is required instead.
  final bool isQuantityOnly;

  const WasteType({
    this.id,
    required this.mainType,
    this.subtypes = const [],
    this.quantityLabels = const {},
    this.isQuantityOnly = false,
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
    );
  }

  Map<String, dynamic> toFirestore() => {
        'mainType': mainType,
        'subtypes': subtypes,
        'quantityLabels': quantityLabels,
        'isQuantityOnly': isQuantityOnly,
      };
}
