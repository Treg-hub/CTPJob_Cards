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

/// Frozen at create on Pulse — import (Siegwerk) vs local reorder loop.
enum InkPurchaseOrderTrack {
  importTrack('import'),
  local('local');

  const InkPurchaseOrderTrack(this.value);
  final String value;

  static InkPurchaseOrderTrack? fromValue(String? v) {
    if (v == null || v.isEmpty) return null;
    for (final t in InkPurchaseOrderTrack.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}

/// Siegwerk sea-freight item codes (mirrors Pulse `SIEGWERK_IMPORT_ITEM_CODES`).
const kSiegwerkImportItemCodes = {
  'yellow',
  'red',
  'blue',
  'black',
  'resink',
  'cellulose',
};

bool isLocalOrderItemCode(String itemCode) =>
    !kSiegwerkImportItemCodes.contains(itemCode);

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
/// Created on Pulse; mobile lists open local POs for Receive Local.
class InkPurchaseOrder {
  const InkPurchaseOrder({
    required this.id,
    required this.pulseRef,
    required this.supplierName,
    required this.status,
    required this.remainingKgByItem,
    this.lines = const [],
    this.track,
    this.erpOrderNumber,
    this.pastelRfoNumber,
    this.estimatedArrival,
  });

  final String id;
  final String pulseRef;
  final String supplierName;
  final InkPurchaseOrderStatus status;
  final Map<String, double> remainingKgByItem;
  final List<InkPurchaseOrderLine> lines;
  final InkPurchaseOrderTrack? track;
  final String? erpOrderNumber;
  final String? pastelRfoNumber;
  final DateTime? estimatedArrival;

  double remainingFor(String itemCode) => remainingKgByItem[itemCode] ?? 0;

  double get totalRemaining =>
      remainingKgByItem.values.fold<double>(0, (a, b) => a + b);

  bool get hasOpenRemaining => totalRemaining > 1e-6;

  /// Prefer frozen [track]; legacy docs fall back to line item codes.
  bool get isLocalTrack {
    if (track == InkPurchaseOrderTrack.local) return true;
    if (track == InkPurchaseOrderTrack.importTrack) return false;
    for (final l in lines) {
      if (l.finalKg > 0 && l.itemCode.isNotEmpty) {
        return isLocalOrderItemCode(l.itemCode);
      }
    }
    for (final code in remainingKgByItem.keys) {
      if (code.isNotEmpty) return isLocalOrderItemCode(code);
    }
    if (lines.isNotEmpty && lines.first.itemCode.isNotEmpty) {
      return isLocalOrderItemCode(lines.first.itemCode);
    }
    // Unknown legacy shape — treat as local so Receive Local still surfaces it.
    return true;
  }

  /// Lines with remaining qty still open for receipt.
  List<({InkPurchaseOrderLine line, double remaining})> get openLines {
    final out = <({InkPurchaseOrderLine line, double remaining})>[];
    final seen = <String>{};
    for (final line in lines) {
      if (line.itemCode.isEmpty || seen.contains(line.itemCode)) continue;
      seen.add(line.itemCode);
      final rem = remainingFor(line.itemCode);
      if (rem > 1e-6) {
        out.add((line: line, remaining: rem));
      }
    }
    // Remaining keys not present on lines (edge / legacy).
    for (final e in remainingKgByItem.entries) {
      if (e.value <= 1e-6 || seen.contains(e.key)) continue;
      seen.add(e.key);
      out.add((
        line: InkPurchaseOrderLine(
          itemCode: e.key,
          displayName: e.key,
          unit: 'KG',
          finalKg: e.value,
        ),
        remaining: e.value,
      ));
    }
    return out;
  }

  factory InkPurchaseOrder.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final remainingRaw =
        d['remaining_kg_by_item'] as Map<String, dynamic>? ?? {};
    final remaining = <String, double>{
      for (final e in remainingRaw.entries)
        e.key: (e.value as num?)?.toDouble() ?? 0,
    };
    final lineMaps =
        ((d['lines'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
    DateTime? eta;
    final etaRaw = d['estimated_arrival'];
    if (etaRaw is Timestamp) {
      eta = etaRaw.toDate();
    }
    return InkPurchaseOrder(
      id: doc.id,
      pulseRef: d['pulse_ref'] as String? ?? doc.id,
      supplierName: d['supplier_name'] as String? ?? '',
      status: InkPurchaseOrderStatus.fromValue(d['status'] as String?),
      remainingKgByItem: remaining,
      lines: lineMaps.map(InkPurchaseOrderLine.fromMap).toList(),
      track: InkPurchaseOrderTrack.fromValue(d['track'] as String?),
      erpOrderNumber: d['erp_order_number'] as String?,
      pastelRfoNumber: d['pastel_rfo_number'] as String?,
      estimatedArrival: eta,
    );
  }
}
