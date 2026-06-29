/// Pure PO receipt deduction — mirrors Pulse `deductReceiptFromPurchaseOrder`.
const double inkPoFulfilledThreshold = 0.5;

typedef PoFulfillmentResult = ({
  Map<String, double> remainingKgByItem,
  String status,
});

typedef ShipmentFulfillmentResult = ({
  Map<String, double> remainingKgByItem,
  String status,
  List<String> linkedShipmentIds,
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

/// Deducts expected kg per shipment line from PO remaining qty.
/// Mirrors Pulse `applyShipmentToPurchaseOrder` deduction logic.
ShipmentFulfillmentResult applyShipmentDeduction({
  required Map<String, double> remainingKgByItem,
  required Iterable<({String itemCode, double expectedKg})> lines,
  required List<String> linkedShipmentIds,
  required String shipmentId,
}) {
  final deduct = <String, double>{};
  for (final line in lines) {
    if (line.itemCode.isEmpty) continue;
    deduct[line.itemCode] =
        (deduct[line.itemCode] ?? 0) + line.expectedKg;
  }

  final remaining = Map<String, double>.from(remainingKgByItem);
  for (final entry in deduct.entries) {
    remaining[entry.key] =
        ((remaining[entry.key] ?? 0) - entry.value).clamp(0, double.infinity);
  }

  final linked = {...linkedShipmentIds, shipmentId}.toList();
  final totalRemaining = remaining.values.fold<double>(0, (a, b) => a + b);
  final status = totalRemaining <= inkPoFulfilledThreshold
      ? 'fulfilled'
      : 'partially_fulfilled';
  return (
    remainingKgByItem: remaining,
    status: status,
    linkedShipmentIds: linked,
  );
}