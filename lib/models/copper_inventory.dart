import 'package:cloud_firestore/cloud_firestore.dart';

class CopperInventory {
  final double sortKg;
  final double reuseKg;
  final double sellKg;
  final double sellRodsKg;
  final double sellNuggetsKg;
  final String? activeCopperWasteBatchId;
  final double currentRPerKg;
  final Timestamp lastUpdated;

  const CopperInventory({
    required this.sortKg,
    required this.reuseKg,
    required this.sellKg,
    this.sellRodsKg = 0.0,
    this.sellNuggetsKg = 0.0,
    this.activeCopperWasteBatchId,
    required this.currentRPerKg,
    required this.lastUpdated,
  });

  factory CopperInventory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final sellKg = (data['sell_kg'] as num?)?.toDouble() ?? 0.0;
    final sellRodsKg = (data['sell_rods_kg'] as num?)?.toDouble() ?? 0.0;
    final sellNuggetsKg = (data['sell_nuggets_kg'] as num?)?.toDouble() ?? 0.0;
    return CopperInventory(
      sortKg: (data['sort_kg'] as num?)?.toDouble() ?? 0.0,
      reuseKg: (data['reuse_kg'] as num?)?.toDouble() ?? 0.0,
      sellKg: sellKg,
      sellRodsKg: sellRodsKg,
      sellNuggetsKg: sellNuggetsKg,
      activeCopperWasteBatchId:
          data['active_copper_waste_batch_id'] as String?,
      currentRPerKg: (data['current_r_per_kg'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: data['last_updated'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sort_kg': sortKg,
      'reuse_kg': reuseKg,
      'sell_kg': sellKg,
      'sell_rods_kg': sellRodsKg,
      'sell_nuggets_kg': sellNuggetsKg,
      if (activeCopperWasteBatchId != null)
        'active_copper_waste_batch_id': activeCopperWasteBatchId,
      'current_r_per_kg': currentRPerKg,
      'last_updated': lastUpdated,
    };
  }

  CopperInventory copyWith({
    double? sortKg,
    double? reuseKg,
    double? sellKg,
    double? sellRodsKg,
    double? sellNuggetsKg,
    String? activeCopperWasteBatchId,
    bool clearActiveCopperWasteBatchId = false,
    double? currentRPerKg,
    Timestamp? lastUpdated,
  }) {
    return CopperInventory(
      sortKg: sortKg ?? this.sortKg,
      reuseKg: reuseKg ?? this.reuseKg,
      sellKg: sellKg ?? this.sellKg,
      sellRodsKg: sellRodsKg ?? this.sellRodsKg,
      sellNuggetsKg: sellNuggetsKg ?? this.sellNuggetsKg,
      activeCopperWasteBatchId: clearActiveCopperWasteBatchId
          ? null
          : (activeCopperWasteBatchId ?? this.activeCopperWasteBatchId),
      currentRPerKg: currentRPerKg ?? this.currentRPerKg,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  double get totalKg => sortKg + reuseKg + sellKg;
  double get estimatedValueR => totalKg * currentRPerKg;
}