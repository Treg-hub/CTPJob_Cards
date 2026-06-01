import 'package:cloud_firestore/cloud_firestore.dart';

/// Master waste type definition (waste_types collection).
/// Defines the main type + its allowed subtypes + how quantity should be labeled in the UI.
class WasteType {
  final String? id;
  final String mainType;
  final List<String> subtypes;
  final Map<String, String> quantityLabels; // subtype -> label, e.g. "Reelends" -> "Quantity (reels)"

  const WasteType({
    this.id,
    required this.mainType,
    this.subtypes = const [],
    this.quantityLabels = const {},
  });

  /// Returns the dynamic quantity label for a given subtype.
  /// Falls back to "Quantity (units)" per spec.
  String quantityLabelFor(String subtype) {
    return quantityLabels[subtype] ?? 'Quantity (units)';
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
    );
  }

  Map<String, dynamic> toFirestore() => {
        'mainType': mainType,
        'subtypes': subtypes,
        'quantityLabels': quantityLabels,
      };
}
