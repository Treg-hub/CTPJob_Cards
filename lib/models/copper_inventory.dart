import 'package:cloud_firestore/cloud_firestore.dart';

class CopperInventory {
  final double sortKg;
  final double reuseKg;
  final double sellKg;
  final double currentRPerKg;
  final Timestamp lastUpdated;

  const CopperInventory({
    required this.sortKg,
    required this.reuseKg,
    required this.sellKg,
    required this.currentRPerKg,
    required this.lastUpdated,
  });

  factory CopperInventory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CopperInventory(
      sortKg: (data['sort_kg'] as num?)?.toDouble() ?? 0.0,
      reuseKg: (data['reuse_kg'] as num?)?.toDouble() ?? 0.0,
      sellKg: (data['sell_kg'] as num?)?.toDouble() ?? 0.0,
      currentRPerKg: (data['current_r_per_kg'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: data['last_updated'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sort_kg': sortKg,
      'reuse_kg': reuseKg,
      'sell_kg': sellKg,
      'current_r_per_kg': currentRPerKg,
      'last_updated': lastUpdated,
    };
  }

  CopperInventory copyWith({
    double? sortKg,
    double? reuseKg,
    double? sellKg,
    double? currentRPerKg,
    Timestamp? lastUpdated,
  }) {
    return CopperInventory(
      sortKg: sortKg ?? this.sortKg,
      reuseKg: reuseKg ?? this.reuseKg,
      sellKg: sellKg ?? this.sellKg,
      currentRPerKg: currentRPerKg ?? this.currentRPerKg,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  double get totalKg => sortKg + reuseKg + sellKg;
  double get estimatedValueR => totalKg * currentRPerKg;
}