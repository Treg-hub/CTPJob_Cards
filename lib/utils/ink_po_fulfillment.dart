// Pure PO receipt deduction — mirrors Pulse / CF `poFulfillment`.
// Exact-zero remaining → fulfilled. Small delivery shortfalls (≤
// inkPoAutoVarianceFraction of ordered) may be auto-written-off by CF after
// local receive. Larger residuals stay open until manager finalize on Pulse.

const double inkPoFulfilledThreshold = 1e-6;

/// Max residual / ordered the server auto-closes without manager approve (1%).
/// Example: ordered 10 000, received 9 944 → residual 56 (0.56%) auto-close.
const double inkPoAutoVarianceFraction = 0.01;

typedef PoFulfillmentResult = ({
  Map<String, double> remainingKgByItem,
  String status,
});

typedef ShipmentFulfillmentResult = ({
  Map<String, double> remainingKgByItem,
  String status,
  List<String> linkedShipmentIds,
});

typedef AutoVarianceResult = ({
  Map<String, double> remainingKgByItem,
  Map<String, double> writeOffKgByItem,
  String status,
});

bool residualWithinAutoVariance({
  required double residual,
  required double ordered,
  double maxFraction = inkPoAutoVarianceFraction,
}) {
  if (residual <= inkPoFulfilledThreshold) return true;
  if (ordered <= 0) return false;
  return residual / ordered <= maxFraction;
}

/// Preview residual after a line receipt (before server auto-variance).
double residualAfterReceipt({
  required double remainingBefore,
  required double quantityReceived,
}) {
  final r = remainingBefore - quantityReceived;
  if (r <= inkPoFulfilledThreshold) return 0;
  return r < 0 ? 0 : r;
}

AutoVarianceResult applyAutoDeliveryVariance({
  required Map<String, double> remainingKgByItem,
  required Map<String, double> orderedKgByItem,
  double maxFraction = inkPoAutoVarianceFraction,
}) {
  final remaining = <String, double>{};
  final writeOff = <String, double>{};
  for (final e in remainingKgByItem.entries) {
    final residual = e.value;
    if (residual <= inkPoFulfilledThreshold) {
      remaining[e.key] = 0;
      continue;
    }
    final ordered = orderedKgByItem[e.key] ?? 0;
    if (ordered > 0 && residual / ordered <= maxFraction) {
      writeOff[e.key] = double.parse(residual.toStringAsFixed(3));
      remaining[e.key] = 0;
    } else {
      remaining[e.key] = residual;
    }
  }
  final total =
      remaining.values.fold<double>(0, (a, b) => a + b);
  return (
    remainingKgByItem: remaining,
    writeOffKgByItem: writeOff,
    status: total <= inkPoFulfilledThreshold ? 'fulfilled' : 'partially_fulfilled',
  );
}

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

/// Deducts received/scanned kg per item from PO remaining qty.
/// Mirrors Pulse `applyShipmentToPurchaseOrder` deduction logic.
ShipmentFulfillmentResult applyShipmentDeduction({
  required Map<String, double> remainingKgByItem,
  required Map<String, double> receivedKgByItem,
  required List<String> linkedShipmentIds,
  required String shipmentId,
}) {
  final deduct = receivedKgByItem;

  final remaining = Map<String, double>.from(remainingKgByItem);
  for (final entry in deduct.entries) {
    if (entry.key.isEmpty || entry.value <= 0) continue;
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
