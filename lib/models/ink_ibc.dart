import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical ink colour codes (itemCode values) in display order.
const kInkColourCodes = ['yellow', 'red', 'blue', 'black'];

/// Display labels corresponding to [kInkColourCodes].
const kInkColourLabels = ['Yellow', 'Red', 'Blue', 'Black'];

/// Lifecycle of an IBC (intermediate bulk container of ink).
enum InkIbcStatus {
  received('received'),
  transferred('transferred');

  const InkIbcStatus(this.value);
  final String value;

  static InkIbcStatus fromValue(String? v) =>
      InkIbcStatus.values.firstWhere((s) => s.value == v,
          orElse: () => InkIbcStatus.received);
}

/// An IBC in the audit register (`ink_ibcs`). Receiving an IBC counts as
/// receiving ink (a batch `purchase` is recorded separately per colour). The
/// IBC is later transferred to a tank, at which point its wash toloul is logged
/// as a `consumption_toloul_wash`. The document id is the IBC number.
class InkIbc {
  const InkIbc({
    this.id,
    required this.ibcNumber,
    required this.itemCode,
    required this.kg,
    this.status = InkIbcStatus.received,
    required this.receivedDate,
    this.supplierName,
    this.transferredDate,
    this.washTolulLitres,
    this.orderNumber,
    this.cgnaNumber,
    this.chargeNumber,
    this.shipmentId,
  });

  final String? id;
  final String ibcNumber;
  final String itemCode; // ink colour
  final double kg;
  final InkIbcStatus status;
  final DateTime receivedDate;
  final String? supplierName;
  final DateTime? transferredDate;
  final double? washTolulLitres;

  /// Purchase order number for the receipt (default supplier Siegwerk).
  final String? orderNumber;

  /// CGNA number captured at receipt.
  final String? cgnaNumber;

  /// Siegwerk batch/lot ("Charge"), from the GS1 barcode (AI 10).
  final String? chargeNumber;

  /// Links this receipt to its `ink_shipments` doc ({order}-{letter}) when the
  /// operator received against a selected shipment. Null for free-text receipts.
  final String? shipmentId;

  /// Accepts [Timestamp], ISO [String], or [DateTime] — one bad legacy field
  /// must not poison the whole IBC list stream.
  static DateTime? parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double parseDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static double? parseOptionalDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Returns null when a document cannot be parsed (skipped in list streams).
  static InkIbc? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return InkIbc.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  factory InkIbc.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkIbc(
      id: doc.id,
      ibcNumber: d['ibc_number'] as String? ?? doc.id,
      itemCode: d['item_code'] as String? ?? '',
      kg: parseDouble(d['kg']),
      status: InkIbcStatus.fromValue(d['status'] as String?),
      receivedDate: parseTimestamp(d['received_date']) ?? DateTime.now(),
      supplierName: d['supplier_name'] as String?,
      transferredDate: parseTimestamp(d['transferred_date']),
      washTolulLitres: parseOptionalDouble(d['wash_toloul_litres']),
      orderNumber: d['order_number'] as String?,
      cgnaNumber: d['cgna_number'] as String?,
      chargeNumber: d['charge_number'] as String?,
      shipmentId: d['shipment_id'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'ibc_number': ibcNumber,
        'item_code': itemCode,
        'kg': kg,
        'status': status.value,
        'received_date': Timestamp.fromDate(receivedDate),
        if (supplierName != null) 'supplier_name': supplierName,
        if (transferredDate != null)
          'transferred_date': Timestamp.fromDate(transferredDate!),
        if (washTolulLitres != null) 'wash_toloul_litres': washTolulLitres,
        if (orderNumber != null) 'order_number': orderNumber,
        if (cgnaNumber != null) 'cgna_number': cgnaNumber,
        if (chargeNumber != null) 'charge_number': chargeNumber,
        if (shipmentId != null) 'shipment_id': shipmentId,
      };
}
