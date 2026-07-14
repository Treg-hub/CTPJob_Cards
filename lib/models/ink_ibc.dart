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
/// as a `consumption_toloul_wash`.
///
/// **Doc id**: legacy stock uses last-8 `ibc_number`; Wave B receipts use full
/// SSCC (18+ digits) when present, with `ibc_number` still last-8. Always prefer
/// [id] (Firestore `doc.id`) for updates — never assume last-8 alone.
class InkIbc {
  const InkIbc({
    this.id,
    this.sscc,
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
    this.damageFlag = false,
    this.damageReason,
    this.damageRecordedAt,
    this.damageRecordedBy,
  });

  final String? id;
  /// Full SSCC when known (18+ digits). Legacy docs may omit this field.
  final String? sscc;
  /// Operator-facing number — always the last 8 digits.
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

  /// True once this physical IBC has been flagged damaged — either by the
  /// operator at consume time (excluded from waste stock entirely) or by a
  /// guard/manager at Begin Collection (removed from a load, not returned to
  /// on-site stock). [damageReason] is required whenever this is true.
  final bool damageFlag;
  final String? damageReason;
  final DateTime? damageRecordedAt;
  /// clockNo of whoever recorded the damage (operator or guard/manager).
  final String? damageRecordedBy;

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
      sscc: d['sscc'] as String?,
      ibcNumber: d['ibc_number'] as String? ??
          (doc.id.length >= 8 ? doc.id.substring(doc.id.length - 8) : doc.id),
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
      damageFlag: d['damage_flag'] as bool? ?? false,
      damageReason: d['damage_reason'] as String?,
      damageRecordedAt: parseTimestamp(d['damage_recorded_at']),
      damageRecordedBy: d['damage_recorded_by'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        if (sscc != null && sscc!.isNotEmpty) 'sscc': sscc,
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
        if (damageFlag) 'damage_flag': damageFlag,
        if (damageReason != null) 'damage_reason': damageReason,
        if (damageRecordedAt != null)
          'damage_recorded_at': Timestamp.fromDate(damageRecordedAt!),
        if (damageRecordedBy != null) 'damage_recorded_by': damageRecordedBy,
      };
}
