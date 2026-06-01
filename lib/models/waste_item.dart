import 'package:cloud_firestore/cloud_firestore.dart';

/// Individual waste item inside a WasteLoad (waste_items collection).
/// Every item must have at least one photo (enforced in UI + service).
class WasteItem {
  final String? id;
  final String loadId;
  final String subtype;
  final String? description;
  final int? quantity; // optional, label is dynamic based on subtype
  final double weightKg; // required
  final String? notes;
  final List<String> photos; // min 1 required

  const WasteItem({
    this.id,
    required this.loadId,
    required this.subtype,
    this.description,
    this.quantity,
    required this.weightKg,
    this.notes,
    this.photos = const [],
  });

  factory WasteItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WasteItem(
      id: doc.id,
      loadId: data['load_id'] as String? ?? '',
      subtype: data['subtype'] as String? ?? '',
      description: data['description'] as String?,
      quantity: (data['quantity'] as num?)?.toInt(),
      weightKg: (data['weight_kg'] as num?)?.toDouble() ?? 0,
      notes: data['notes'] as String?,
      photos: (data['photos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'load_id': loadId,
      'subtype': subtype,
      'description': description,
      'quantity': quantity,
      'weight_kg': weightKg,
      'notes': notes,
      'photos': photos,
    };
  }

  WasteItem copyWith({
    String? id,
    String? loadId,
    String? subtype,
    String? description,
    int? quantity,
    double? weightKg,
    String? notes,
    List<String>? photos,
  }) {
    return WasteItem(
      id: id ?? this.id,
      loadId: loadId ?? this.loadId,
      subtype: subtype ?? this.subtype,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      weightKg: weightKg ?? this.weightKg,
      notes: notes ?? this.notes,
      photos: photos ?? this.photos,
    );
  }
}
