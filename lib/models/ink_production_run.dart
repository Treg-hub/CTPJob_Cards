import 'package:cloud_firestore/cloud_firestore.dart';

/// A recorded production run (`ink_production_runs`) — header/audit for a batch.
/// The actual stock movements are the linked consumption_production + manufacture
/// transactions (productionRunId).
class InkProductionRun {
  const InkProductionRun({
    required this.id,
    required this.recipeName,
    required this.outputItemCode,
    required this.pots,
    required this.outputQty,
    required this.totalInputCost,
    required this.effectiveAt,
    this.actorName,
  });

  final String id;
  final String recipeName;
  final String outputItemCode;
  final int pots;
  final double outputQty;
  final double totalInputCost;
  final DateTime effectiveAt;
  final String? actorName;

  factory InkProductionRun.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkProductionRun(
      id: doc.id,
      recipeName: d['recipe_name'] as String? ?? '',
      outputItemCode: d['output_item_code'] as String? ?? '',
      pots: (d['pots'] as num?)?.toInt() ?? 0,
      outputQty: (d['output_qty'] as num?)?.toDouble() ?? 0,
      totalInputCost: (d['total_input_cost'] as num?)?.toDouble() ?? 0,
      effectiveAt: (d['effective_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      actorName: d['actor_name'] as String?,
    );
  }
}
