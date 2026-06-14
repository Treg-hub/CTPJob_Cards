import 'package:cloud_firestore/cloud_firestore.dart';

import 'ink_txn_type.dart';
import '../services/ink_ledger.dart';

/// Deferred-cost state of a `purchase` transaction. Mirrors Fleet's
/// `cost_status`: a receipt is captured `pending` (quantity only) and the
/// manager later enters the shipment cost, flipping it to `costed`, which
/// triggers a WAC re-replay. `na` is used for types where cost is irrelevant.
enum InkCostStatus {
  pending('pending'),
  costed('costed'),
  na('na');

  const InkCostStatus(this.value);
  final String value;

  static InkCostStatus fromValue(String? value) =>
      InkCostStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => InkCostStatus.na,
      );
}

/// One immutable row in the append-only ledger (`ink_transactions`).
///
/// `balanceBefore` / `balanceAfter` / `wacAtTime` are CACHED outputs of the
/// server-authoritative replay — clients never compute or write them directly.
/// Ordering for balance/WAC is by [effectiveAt] (when it happened); [recordedAt]
/// (server time) drives the `INK####` sequence and the audit trail.
class InkTransaction {
  const InkTransaction({
    this.id,
    this.seqNumber,
    required this.type,
    required this.stockItemCode,
    required this.quantityDelta,
    required this.effectiveAt,
    this.recordedAt,
    this.totalCost,
    this.newWac,
    this.costStatus = InkCostStatus.na,
    this.voided = false,
    this.balanceBefore = 0,
    this.balanceAfter = 0,
    this.wacAtTime = 0,
    required this.actorClockNo,
    required this.actorName,
    required this.idempotencyKey,
    this.flaggedForReview = false,
    this.flagReason,
    this.reason,
    this.notes,
    this.relatedTransactionId,
    this.productionRunId,
    this.sessionId,
    this.ibcNumber,
    this.lurgiSource,
    this.supplierName,
    this.litresEntered,
    this.conversionFactorUsed,
    this.meterReading,
    this.readingDate,
  });

  final String? id;

  /// Human-readable sequence `INK####`, strictly sequential, server-assigned at
  /// commit. Null until the queued entry syncs (operator sees "pending #").
  final String? seqNumber;

  final InkTxnType type;
  final String stockItemCode;

  /// Signed quantity change (deductions negative; transfer/revaluation 0).
  final double quantityDelta;

  /// When the movement actually happened (operator-chosen; drives replay order).
  final DateTime effectiveAt;

  /// Server timestamp when the row was committed.
  final DateTime? recordedAt;

  /// Total value in — purchase price or manufacture input cost. Null until a
  /// pending purchase is costed.
  final double? totalCost;

  /// New WAC to set, for `revaluation` only.
  final double? newWac;

  final InkCostStatus costStatus;

  /// Voided by a correction — preserved for audit, excluded from replay.
  final bool voided;

  // Cached ledger outputs (written by the server replay).
  final double balanceBefore;
  final double balanceAfter;
  final double wacAtTime;

  final String actorClockNo;
  final String actorName;
  final String idempotencyKey;

  final bool flaggedForReview;
  final String? flagReason;
  final String? reason;
  final String? notes;

  // Context links (nullable, per movement kind).
  final String? relatedTransactionId;
  final String? productionRunId;
  final String? sessionId;
  final String? ibcNumber;
  final String? lurgiSource;

  /// Supplier name (denormalised from the managed list) for `purchase` receipts.
  final String? supplierName;
  final double? litresEntered;
  final double? conversionFactorUsed;

  /// Cumulative meter value for a `consumption_meter` reading (used to compute
  /// the next reading's delta). Null for direct-consumption ("manual") entries.
  final double? meterReading;
  final DateTime? readingDate;

  /// Bridge to the pure costing engine. A `purchase` still awaiting its cost is
  /// treated as provisional (quantity in at current WAC) until costed.
  LedgerEntry toLedgerEntry() => LedgerEntry(
        type: type,
        effectiveAt: effectiveAt,
        quantityDelta: quantityDelta,
        totalCost: totalCost,
        newWac: newWac,
        costPending:
            type == InkTxnType.purchase && costStatus == InkCostStatus.pending,
        voided: voided,
      );

  factory InkTransaction.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    double? num2(String k) => (d[k] as num?)?.toDouble();
    DateTime? ts(String k) => (d[k] as Timestamp?)?.toDate();
    return InkTransaction(
      id: doc.id,
      seqNumber: d['seq_number'] as String?,
      type: InkTxnType.fromValue(d['type'] as String?),
      stockItemCode: d['stock_item_code'] as String? ?? '',
      quantityDelta: num2('quantity_delta') ?? 0,
      effectiveAt: ts('effective_at') ?? DateTime.now(),
      recordedAt: ts('recorded_at'),
      totalCost: num2('total_cost'),
      newWac: num2('new_wac'),
      costStatus: InkCostStatus.fromValue(d['cost_status'] as String?),
      voided: d['voided'] as bool? ?? false,
      balanceBefore: num2('balance_before') ?? 0,
      balanceAfter: num2('balance_after') ?? 0,
      wacAtTime: num2('wac_at_time') ?? 0,
      actorClockNo: d['actor_clock_no'] as String? ?? '',
      actorName: d['actor_name'] as String? ?? '',
      idempotencyKey: d['idempotency_key'] as String? ?? '',
      flaggedForReview: d['flagged_for_review'] as bool? ?? false,
      flagReason: d['flag_reason'] as String?,
      reason: d['reason'] as String?,
      notes: d['notes'] as String?,
      relatedTransactionId: d['related_transaction_id'] as String?,
      productionRunId: d['production_run_id'] as String?,
      sessionId: d['session_id'] as String?,
      ibcNumber: d['ibc_number'] as String?,
      lurgiSource: d['lurgi_source'] as String?,
      supplierName: d['supplier_name'] as String?,
      litresEntered: num2('litres_entered'),
      conversionFactorUsed: num2('conversion_factor_used'),
      meterReading: num2('meter_reading'),
      readingDate: ts('reading_date'),
    );
  }

  /// Serialises the operator-supplied fields. The cached ledger outputs
  /// (`balance_*`, `wac_at_time`), `seq_number`, and `recorded_at` are written
  /// by the server write path, not here.
  Map<String, dynamic> toFirestore() => {
        'type': type.value,
        'stock_item_code': stockItemCode,
        'quantity_delta': quantityDelta,
        'effective_at': Timestamp.fromDate(effectiveAt),
        'recorded_at': FieldValue.serverTimestamp(),
        if (totalCost != null) 'total_cost': totalCost,
        if (newWac != null) 'new_wac': newWac,
        'cost_status': costStatus.value,
        'voided': voided,
        'actor_clock_no': actorClockNo,
        'actor_name': actorName,
        'idempotency_key': idempotencyKey,
        'flagged_for_review': flaggedForReview,
        if (flagReason != null) 'flag_reason': flagReason,
        if (reason != null) 'reason': reason,
        if (notes != null) 'notes': notes,
        if (relatedTransactionId != null)
          'related_transaction_id': relatedTransactionId,
        if (productionRunId != null) 'production_run_id': productionRunId,
        if (sessionId != null) 'session_id': sessionId,
        if (ibcNumber != null) 'ibc_number': ibcNumber,
        if (lurgiSource != null) 'lurgi_source': lurgiSource,
        if (supplierName != null) 'supplier_name': supplierName,
        if (litresEntered != null) 'litres_entered': litresEntered,
        if (conversionFactorUsed != null)
          'conversion_factor_used': conversionFactorUsed,
        if (meterReading != null) 'meter_reading': meterReading,
        if (readingDate != null) 'reading_date': Timestamp.fromDate(readingDate!),
      };

  /// Partially clones this transaction, overriding only the fields the server
  /// replay patches back (cached balance outputs, WAC, cost fields, flags).
  /// All operator-supplied context fields (reason, ibc, supplier, meter reading,
  /// etc.) are always forwarded from [this] unchanged.
  InkTransaction copyWith({
    String? id,
    String? seqNumber,
    double? totalCost,
    InkCostStatus? costStatus,
    double? balanceBefore,
    double? balanceAfter,
    double? wacAtTime,
    bool? flaggedForReview,
    String? flagReason,
    bool? voided,
  }) =>
      InkTransaction(
        id: id ?? this.id,
        seqNumber: seqNumber ?? this.seqNumber,
        type: type,
        stockItemCode: stockItemCode,
        quantityDelta: quantityDelta,
        effectiveAt: effectiveAt,
        recordedAt: recordedAt,
        totalCost: totalCost ?? this.totalCost,
        newWac: newWac,
        costStatus: costStatus ?? this.costStatus,
        voided: voided ?? this.voided,
        balanceBefore: balanceBefore ?? this.balanceBefore,
        balanceAfter: balanceAfter ?? this.balanceAfter,
        wacAtTime: wacAtTime ?? this.wacAtTime,
        actorClockNo: actorClockNo,
        actorName: actorName,
        idempotencyKey: idempotencyKey,
        flaggedForReview: flaggedForReview ?? this.flaggedForReview,
        flagReason: flagReason ?? this.flagReason,
        reason: reason,
        notes: notes,
        relatedTransactionId: relatedTransactionId,
        productionRunId: productionRunId,
        sessionId: sessionId,
        ibcNumber: ibcNumber,
        lurgiSource: lurgiSource,
        litresEntered: litresEntered,
        conversionFactorUsed: conversionFactorUsed,
        meterReading: meterReading,
        readingDate: readingDate,
      );
}
