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
  /// Rate snapshot captured from waste_rates at collection time.
  /// For weight-based items: R/kg. For quantity-only items: R/unit.
  /// Null means no rate was found; admin must enter it on cost review.
  final double? ratePerKg;
  /// Snapshot of WasteType.isQuantityOnly at recording time.
  /// When true: measured by count not weight; ratePerKg is treated as rate per unit.
  final bool isQuantityOnly;
  /// Snapshot of WasteType.noSiteWeight — weight confirmed at weighbridge, not on-site.
  final bool isNoSiteWeight;
  /// Snapshot of WasteType.isFixedTareDualBin (e.g. Copper Skins).
  final bool isFixedTareDualBin;
  /// Full Bin 1 weight on scale (kg). Dual-bin only.
  final double? grossBin1Kg;
  /// Full Bin 2 weight on scale (kg). Dual-bin only.
  final double? grossBin2Kg;
  /// Empty Bin 1 tare snapshotted from settings at capture (kg). Dual-bin only.
  final double? tareBin1Kg;
  /// Empty Bin 2 tare snapshotted from settings at capture (kg). Dual-bin only.
  final double? tareBin2Kg;

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
    this.isQuantityOnly = false,
    this.isNoSiteWeight = false,
    this.isFixedTareDualBin = false,
    this.grossBin1Kg,
    this.grossBin2Kg,
    this.tareBin1Kg,
    this.tareBin2Kg,
  });

  /// Line value: for quantity-only items uses qty × rate; for weight-based uses kg × rate.
  double? get lineValue {
    if (ratePerKg == null) return null;
    if (isQuantityOnly) return (quantity ?? 0) * ratePerKg!;
    return weightKg * ratePerKg!;
  }

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
      isQuantityOnly: data['is_quantity_only'] as bool? ?? false,
      isNoSiteWeight: data['is_no_site_weight'] as bool? ?? false,
      isFixedTareDualBin: data['is_fixed_tare_dual_bin'] as bool? ?? false,
      grossBin1Kg: (data['gross_bin1_kg'] as num?)?.toDouble(),
      grossBin2Kg: (data['gross_bin2_kg'] as num?)?.toDouble(),
      tareBin1Kg: (data['tare_bin1_kg'] as num?)?.toDouble(),
      tareBin2Kg: (data['tare_bin2_kg'] as num?)?.toDouble(),
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
      'is_quantity_only': isQuantityOnly,
      'is_no_site_weight': isNoSiteWeight,
      'is_fixed_tare_dual_bin': isFixedTareDualBin,
      if (grossBin1Kg != null) 'gross_bin1_kg': grossBin1Kg,
      if (grossBin2Kg != null) 'gross_bin2_kg': grossBin2Kg,
      if (tareBin1Kg != null) 'tare_bin1_kg': tareBin1Kg,
      if (tareBin2Kg != null) 'tare_bin2_kg': tareBin2Kg,
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
    bool? isQuantityOnly,
    bool? isNoSiteWeight,
    bool? isFixedTareDualBin,
    double? grossBin1Kg,
    double? grossBin2Kg,
    double? tareBin1Kg,
    double? tareBin2Kg,
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
      isQuantityOnly: isQuantityOnly ?? this.isQuantityOnly,
      isNoSiteWeight: isNoSiteWeight ?? this.isNoSiteWeight,
      isFixedTareDualBin: isFixedTareDualBin ?? this.isFixedTareDualBin,
      grossBin1Kg: grossBin1Kg ?? this.grossBin1Kg,
      grossBin2Kg: grossBin2Kg ?? this.grossBin2Kg,
      tareBin1Kg: tareBin1Kg ?? this.tareBin1Kg,
      tareBin2Kg: tareBin2Kg ?? this.tareBin2Kg,
    );
  }
}
