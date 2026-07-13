import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of an import shipment (mirrors `ink_shipments.status` in Pulse).
enum InkShipmentStatus {
  awaitingReceipt('awaiting_receipt'),
  receiving('receiving'),
  received('received'),
  awaitingGrn('awaiting_grn'),
  costed('costed');

  const InkShipmentStatus(this.value);
  final String value;

  static InkShipmentStatus fromValue(String? v) =>
      InkShipmentStatus.values.firstWhere((s) => s.value == v,
          orElse: () => InkShipmentStatus.awaitingReceipt);
}

/// A unit recorded on `ink_shipments.received_units` after mobile receive.
class InkReceivedUnit {
  const InkReceivedUnit({
    required this.ref,
    required this.itemCode,
    required this.netKg,
    this.scannedAt,
  });

  final String ref;
  final String itemCode;
  final double netKg;
  final DateTime? scannedAt;

  factory InkReceivedUnit.fromMap(Map<String, dynamic> m) {
    final scannedRaw = m['scanned_at'];
    return InkReceivedUnit(
      ref: m['ref'] as String? ?? '',
      itemCode: m['item_code'] as String? ?? '',
      netKg: (m['net_kg'] as num?)?.toDouble() ?? 0,
      scannedAt: scannedRaw is Timestamp ? scannedRaw.toDate() : null,
    );
  }
}

/// An expected unit (IBC serial / pallet) from the packing list.
class InkExpectedUnit {
  const InkExpectedUnit({
    required this.sscc,
    required this.itemCode,
    this.batch,
    required this.netKg,
  });

  final String sscc;
  final String itemCode;
  final String? batch;
  final double netKg;

  /// The 8-digit IBC number an operator scans/types is the last 8 of the SSCC
  /// (the GS1 barcode parser derives it the same way).
  String get ibcNumber =>
      sscc.length >= 8 ? sscc.substring(sscc.length - 8) : sscc;

  factory InkExpectedUnit.fromMap(Map<String, dynamic> m) => InkExpectedUnit(
        sscc: m['sscc'] as String? ?? '',
        itemCode: m['item_code'] as String? ?? '',
        batch: m['batch'] as String?,
        netKg: (m['net_kg'] as num?)?.toDouble() ?? 0,
      );
}

/// An invoice line (colour / material) expected on the shipment.
class InkShipmentLine {
  const InkShipmentLine({
    required this.itemCode,
    required this.expectedKg,
    this.description,
  });

  final String itemCode;
  final double expectedKg;
  final String? description;

  factory InkShipmentLine.fromMap(Map<String, dynamic> m) => InkShipmentLine(
        itemCode: m['item_code'] as String? ?? '',
        expectedKg: (m['expected_kg'] as num?)?.toDouble() ?? 0,
        description: m['description'] as String?,
      );
}

/// A Siegwerk import shipment (`ink_shipments`). Created + costed in Pulse;
/// read-only on mobile where an operator receives stock against it. The
/// document id is `{orderNumber}-{containerLetter}` (e.g. `51993-K`).
class InkShipment {
  const InkShipment({
    required this.id,
    required this.orderNumber,
    required this.containerLetter,
    required this.packagingMode,
    required this.status,
    this.cgnaNumber,
    this.containerNumber,
    this.purchaseOrderId,
    this.lines = const [],
    this.expectedUnits = const [],
    this.receivedUnits = const [],
    this.updatedAt,
  });

  final String id;
  final String orderNumber;
  final String containerLetter;
  final String packagingMode; // 'ibc' | 'pallet'
  final InkShipmentStatus status;
  final String? cgnaNumber;
  final String? containerNumber;
  final String? purchaseOrderId;
  final List<InkShipmentLine> lines;
  final List<InkExpectedUnit> expectedUnits;
  final List<InkReceivedUnit> receivedUnits;
  final DateTime? updatedAt;

  bool get isIbc => packagingMode == 'ibc';

  int get expectedIbcCount => expectedUnits.length;

  int get receivedIbcCount => receivedUnits.length;

  bool get isReceiptComplete =>
      expectedIbcCount == 0 || receivedIbcCount >= expectedIbcCount;

  /// Distinct item codes expected on this shipment (for the colour dropdown).
  List<String> get itemCodes =>
      {for (final l in lines) l.itemCode}.toList(growable: false);

  /// Prefer latest unit scan; fall back to shipment [updatedAt].
  DateTime? get receivedAtForPeriod {
    DateTime? latest;
    for (final u in receivedUnits) {
      final at = u.scannedAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest ?? updatedAt;
  }

  factory InkShipment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    List<Map<String, dynamic>> maps(String k) =>
        ((d[k] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
    final updatedRaw = d['updated_at'];
    return InkShipment(
      id: doc.id,
      orderNumber: d['order_number'] as String? ?? '',
      containerLetter: d['container_letter'] as String? ?? '',
      packagingMode: d['packaging_mode'] as String? ?? 'ibc',
      status: InkShipmentStatus.fromValue(d['status'] as String?),
      cgnaNumber: d['cgna_number'] as String?,
      containerNumber: d['container_number'] as String?,
      purchaseOrderId: d['purchase_order_id'] as String?,
      lines: maps('lines').map(InkShipmentLine.fromMap).toList(),
      expectedUnits: maps('expected_units').map(InkExpectedUnit.fromMap).toList(),
      receivedUnits: maps('received_units').map(InkReceivedUnit.fromMap).toList(),
      updatedAt: updatedRaw is Timestamp ? updatedRaw.toDate() : null,
    );
  }
}
