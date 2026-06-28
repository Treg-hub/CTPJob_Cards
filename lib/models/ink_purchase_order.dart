import 'package:cloud_firestore/cloud_firestore.dart';

/// Open PO statuses that still have inbound qty (mirrors Pulse inboundPipeline).
enum InkPurchaseOrderStatus {
  sent('sent'),
  partiallyFulfilled('partially_fulfilled'),
  fulfilled('fulfilled');

  const InkPurchaseOrderStatus(this.value);
  final String value;

  static InkPurchaseOrderStatus fromValue(String? v) =>
      InkPurchaseOrderStatus.values.firstWhere(
        (s) => s.value == v,
        orElse: () => InkPurchaseOrderStatus.sent,
      );
}

class InkPurchaseOrderLine {
  const InkPurchaseOrderLine({
    required this.itemCode,
    required this.displayName,
    required this.unit,
    required this.finalKg,
  });

  final String itemCode;
  final String displayName;
  final String unit;
  final double finalKg;

  factory InkPurchaseOrderLine.fromMap(Map<String, dynamic> m) =>
      InkPurchaseOrderLine(
        itemCode: m['item_code'] as String? ?? '',
        displayName: m['display_name'] as String? ?? '',
        unit: m['unit'] as String? ?? 'KG',
        finalKg: (m['final_kg'] as num?)?.toDouble() ?? 0,
      );
}

/// Sent / partially fulfilled purchase order (`ink_purchase_orders`).
/// Created on Pulse; mobile reads open POs to link raw-material receipts.
class InkPurchaseOrder {
  const InkPurchaseOrder({
    required this.id,
    required this.pulseRef,
    required this.supplierName,
    required this.status,
    required this.remainingKgByItem,
    this.lines = const [],
  });

  final String id;
  final String pulseRef;
  final String supplierName;
  final InkPurchaseOrderStatus status;
  final Map<String, double> remainingKgByItem;
  final List<InkPurchaseOrderLine> lines;

  double remainingFor(String itemCode) => remainingKgByItem[itemCode] ?? 0;

  factory InkPurchaseOrder.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final remainingRaw = d['remaining_kg_by_item'] as Map<String, dynamic>? ?? {};
    final remaining = <String, double>{
      for (final e in remainingRaw.entries)
        e.key: (e.value as num?)?.toDouble() ?? 0,
    };
    final lineMaps =
        ((d['lines'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
    return InkPurchaseOrder(
      id: doc.id,
      pulseRef: d['pulse_ref'] as String? ?? doc.id,
      supplierName: d['supplier_name'] as String? ?? '',
      status: InkPurchaseOrderStatus.fromValue(d['status'] as String?),
      remainingKgByItem: remaining,
      lines: lineMaps.map(InkPurchaseOrderLine.fromMap).toList(),
    );
  }
}