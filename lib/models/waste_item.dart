import 'package:cloud_firestore/cloud_firestore.dart';

/// Individual waste item inside a WasteLoad (waste_items collection).
/// Every item must have at least one photo (enforced in UI + service).
class WasteItem {
  final String? id;
  final String loadId;
  final String subtype;
  final String? description;
  final int? quantity;
  final double weightKg;
  final String? notes;
  final List<String> photos;
  /// Set when this item was created from a waste_stock pre-loaded item.
  /// Used to revert the stock item to on_site if this item is deleted.
  final String? sourceStockId;
  /// Soft-delete flag. Deleted items are filtered out of all queries.
  final bool isDeleted;
  /// Rate snapshot captured from waste_rates at collection time (R/kg).
  /// Null means no rate was found; admin must enter it on cost review.
  final double? ratePerKg;

  const WasteItem({
    this.id,
    required this.loadId,
    required this.subtype,
    this.description,
    this.quantity,
    required this.weightKg,
    this.notes,
    this.photos = const [],
    this.sourceStockId,
    this.isDeleted = false,
    this.ratePerKg,
  });

  /// Line value computed on the fly; never stored separately.
  double? get lineValue => ratePerKg != null ? weightKg * ratePerKg! : null;

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
      sourceStockId: data['source_stock_id'] as String?,
      isDeleted: data['is_deleted'] as bool? ?? false,
      ratePerKg: (data['rate_per_kg'] as num?)?.toDouble(),
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
      if (sourceStockId != null) 'source_stock_id': sourceStockId,
      'is_deleted': isDeleted,
      if (ratePerKg != null) 'rate_per_kg': ratePerKg,
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
    String? sourceStockId,
    bool? isDeleted,
    double? ratePerKg,
    bool clearRatePerKg = false,
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
      sourceStockId: sourceStockId ?? this.sourceStockId,
      isDeleted: isDeleted ?? this.isDeleted,
      ratePerKg: clearRatePerKg ? null : (ratePerKg ?? this.ratePerKg),
    );
  }
}
