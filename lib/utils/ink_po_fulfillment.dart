/// Pure PO receipt deduction — mirrors Pulse `deductReceiptFromPurchaseOrder`.
const double inkPoFulfilledThreshold = 0.5;

typedef PoFulfillmentResult = ({
  Map<String, double> remainingKgByItem,
  String status,
});

PoFulfillmentResult deductReceiptFromPurchaseOrder({
  required Map<String, double> remainingKgByItem,
  required String itemCode,
  required double quantity,
}) {
  final remaining = Map<String, double>.from(remainingKgByItem);
  remaining[itemCode] =
      ((remaining[itemCode] ?? 0) - quantity).clamp(0, double.infinity);
  final totalRemaining =
      remaining.values.fold<double>(0, (a, b) => a + b);
  final status = totalRemaining <= inkPoFulfilledThreshold
      ? 'fulfilled'
      : 'partially_fulfilled';
  return (remainingKgByItem: remaining, status: status);
}