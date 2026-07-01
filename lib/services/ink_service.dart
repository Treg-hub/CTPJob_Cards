import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/ink_conversion_factor.dart';
import '../models/ink_count_event.dart';
import '../models/ink_daily_readings_status.dart';
import '../models/ink_ibc.dart';
import '../models/ink_meter_point.dart';
import '../models/ink_production_run.dart';
import '../models/ink_purchase_order.dart';
import '../models/ink_recipe.dart';
import '../models/ink_shipment.dart';
import '../utils/ink_po_fulfillment.dart';
import '../models/ink_settings.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_supplier.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../utils/persona_audit.dart';
import 'waste_stock_crosslink.dart';

/// All Ink Factory Firestore operations. Follows the FleetService/WasteService
/// singleton pattern.
///
/// OFFLINE: every write here is a plain Firestore doc write, so the SDK's
/// built-in offline persistence queues it on poor signal and replays it on
/// reconnect. The server trigger (`onInkTransactionWritten`) then assigns the
/// `INK-####`, recomputes balance/WAC by `effective_at`, and updates the
/// stock-item cache. Until a queued entry reaches the server the operator sees
/// a "pending #" and a provisional balance — by design.
class InkService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  void _guardWrite() => assertPersonaSubmitAllowed();

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------

  Stream<InkSettings> watchSettings() => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .snapshots()
      .map((s) => s.exists ? InkSettings.fromFirestore(s) : InkSettings.defaults);

  Future<void> saveSettings(InkSettings settings) async {
    _guardWrite();
    await _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(settings.toFirestore(), SetOptions(merge: true));
  }

  /// Adds [periodKey] to `closed_periods`.
  Future<void> closePeriod(String periodKey) async {
    _guardWrite();
    await _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(
        {'closed_periods': FieldValue.arrayUnion([periodKey])},
        SetOptions(merge: true),
      );
  }

  /// Removes [periodKey] from both `closed_periods` and
  /// `periods_needing_reissue`.
  Future<void> reopenPeriod(String periodKey) async {
    _guardWrite();
    await _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(
        {
          'closed_periods': FieldValue.arrayRemove([periodKey]),
          'periods_needing_reissue': FieldValue.arrayRemove([periodKey]),
        },
        SetOptions(merge: true),
      );
  }

  /// Adds [periodKey] to `periods_needing_reissue` (manager-override was used
  /// to post into a finalised period).
  Future<void> flagPeriodForReissue(String periodKey) => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(
        {'periods_needing_reissue': FieldValue.arrayUnion([periodKey])},
        SetOptions(merge: true),
      );

  /// Removes [periodKey] from `periods_needing_reissue` (report has been
  /// re-issued and the flag can be cleared).
  Future<void> clearReissue(String periodKey) => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(
        {'periods_needing_reissue': FieldValue.arrayRemove([periodKey])},
        SetOptions(merge: true),
      );

  // ---------------------------------------------------------------------------
  // STOCK ITEMS (cache of the ledger — read-only on the client)
  // ---------------------------------------------------------------------------

  Stream<List<InkStockItem>> watchStockItems({bool activeOnly = true}) => _db
      .collection(Collections.inkStockItems)
      .snapshots()
      .map((s) {
        final items = s.docs.map(InkStockItem.fromFirestore).toList();
        final filtered = activeOnly ? items.where((i) => i.active).toList() : items;
        // Fixed display order (legacy ITEMID), not alphabetical.
        filtered.sort((a, b) {
          final c = a.displayOrder.compareTo(b.displayOrder);
          return c != 0 ? c : a.displayName.compareTo(b.displayName);
        });
        return filtered;
      });

  Stream<InkStockItem?> watchStockItem(String itemCode) => _db
      .collection(Collections.inkStockItems)
      .doc(itemCode)
      .snapshots()
      .map((s) => s.exists ? InkStockItem.fromFirestore(s) : null);

  // ---------------------------------------------------------------------------
  // LEDGER
  // ---------------------------------------------------------------------------

  /// Records a transaction. The [InkTransaction.idempotencyKey] is used as the
  /// document id so an offline replay / retry never duplicates the entry.
  /// Server-computed fields (seq, balance, WAC) are filled by the trigger.
  ///
  /// For named idempotency keys, uses a Firestore transaction to check
  /// existence before writing — prevents a permission-denied error when a
  /// retry hits an existing doc (rules treat .set() on existing as UPDATE,
  /// which is blocked by the hasOnly whitelist).
  Future<void> recordTransaction(InkTransaction txn) async {
    assertPersonaSubmitAllowed();
    final key =
        txn.idempotencyKey.isNotEmpty ? txn.idempotencyKey : _uuid.v4();
    final ref = _db.collection(Collections.inkTransactions).doc(key);
    final data = {...txn.toFirestore(), ...personaAuditFields()};

    if (txn.idempotencyKey.isNotEmpty) {
      await _db.runTransaction((txnObj) async {
        final snap = await txnObj.get(ref);
        if (snap.exists) return; // already recorded — idempotent skip
        txnObj.set(ref, data);
      });
    } else {
      await ref.set(data);
    }
  }

  /// Manager: enter/correct the cost on a pending receipt → flips to `costed`
  /// and triggers a WAC re-replay server-side.
  Future<void> setPurchaseCost(String txnId, double totalCost) async {
    _guardWrite();
    await _db
        .collection(Collections.inkTransactions)
        .doc(txnId)
        .update({
      'total_cost': totalCost,
      'cost_status': InkCostStatus.costed.value,
    });
  }

  /// Manager: correct the effective date on a pending (uncosted) receipt.
  /// The server trigger re-replays from [effectiveAt] when the cost is later saved.
  Future<void> setReceiptEffectiveAt(String txnId, DateTime effectiveAt) => _db
      .collection(Collections.inkTransactions)
      .doc(txnId)
      .update({'effective_at': Timestamp.fromDate(effectiveAt)});

  /// All count events ordered by count date descending (manager history).
  Stream<List<InkCountEvent>> watchCountEvents() => _db
      .collection(Collections.inkCountEvents)
      .orderBy('count_date', descending: true)
      .snapshots()
      .map((s) {
        final list = <InkCountEvent>[];
        for (final doc in s.docs) {
          final event = InkCountEvent.tryFromFirestore(doc);
          if (event != null) {
            list.add(event);
          } else {
            assert(() {
              debugPrint('Skipping unparseable ink_count_events/${doc.id}');
              return true;
            }());
          }
        }
        return list;
      });

  /// Records a month-end count on a designated [countDate] (which need not be
  /// the calendar month-end). Always writes a count-event document so the
  /// session is recorded even when every item matches the ledger. For each item
  /// whose physical count differs from the ledger balance an `adjustment`
  /// transaction is written; all share the same sessionId.
  Future<void> recordMonthEndCount({
    required DateTime countDate,
    required List<
            ({String itemCode, double counted, double ledgerBalance, double wac})>
        lines,
    required String actorClockNo,
    required String actorName,
  }) async {
    _guardWrite();
    final sessionId = _uuid.v4();
    final adjustments = lines.where((l) => (l.counted - l.ledgerBalance).abs() >= 1e-9).toList();

    // Write the count-event record unconditionally — even a zero-variance count
    // needs to be visible as a period boundary in the month-end report. Each line
    // carries the WAC + value snapshot (snapshotVersion 1) so the report can use
    // this count as the opening baseline for the next period instead of replaying
    // the ledger from genesis.
    await _db.collection(Collections.inkCountEvents).doc(sessionId).set(
          InkCountEvent(
            countDate: countDate,
            sessionId: sessionId,
            actorClockNo: actorClockNo,
            actorName: actorName,
            adjustmentCount: adjustments.length,
            snapshotVersion: 1,
            lines: [
              for (final l in lines)
                InkCountLine(
                  itemCode: l.itemCode,
                  counted: l.counted,
                  ledgerBalance: l.ledgerBalance,
                  // The count adjustment moves quantity at the current WAC, so the
                  // post-count WAC equals the WAC captured here.
                  wac: l.wac,
                  value: l.counted * l.wac,
                )
            ],
            createdAt: DateTime.now(),
          ).toFirestore(),
        );

    for (final l in adjustments) {
      await recordTransaction(InkTransaction(
        type: InkTxnType.adjustment,
        stockItemCode: l.itemCode,
        quantityDelta: l.counted - l.ledgerBalance,
        effectiveAt: countDate,
        costStatus: InkCostStatus.na,
        reason: 'Month-end count',
        sessionId: sessionId,
        actorClockNo: actorClockNo,
        actorName: actorName,
        idempotencyKey: '${sessionId}_adj_${l.itemCode}',
      ));
    }

    await _appendMonthlyConsumptionSnapshot(countDate, actorName: actorName);
  }

  static const _consumptionTxnTypeValues = {
    'consumption_meter',
    'consumption_production',
    'consumption_toloul_wash',
    'consumption_toloul_production',
  };

  /// Rolls up consumption txns for the count month into consumption_baseline
  /// and refreshes manufacturing_config binder ratio (incremental, not full ledger).
  Future<void> _appendMonthlyConsumptionSnapshot(
    DateTime countDate, {
    String? actorName,
  }) async {
    final ym =
        '${countDate.year}-${countDate.month.toString().padLeft(2, '0')}';
    final monthStart = DateTime(countDate.year, countDate.month, 1);
    final monthEnd =
        DateTime(countDate.year, countDate.month + 1, 0, 23, 59, 59, 999);

    final snap = await _db
        .collection(Collections.inkTransactions)
        .where('effective_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('effective_at', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
        .get();

    final monthTotals = <String, double>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['voided'] as bool? ?? false) continue;
      final type = d['type'] as String? ?? '';
      if (!_consumptionTxnTypeValues.contains(type)) continue;
      final code = d['stock_item_code'] as String? ?? '';
      if (code.isEmpty) continue;
      final qty = ((d['quantity_delta'] as num?)?.toDouble() ?? 0).abs();
      if (qty <= 0) continue;
      monthTotals[code] = (monthTotals[code] ?? 0) + qty;
    }

    final baselineRef =
        _db.collection(Collections.inkSettings).doc('consumption_baseline');
    final baselineSnap = await baselineRef.get();
    final existingSeries = Map<String, Map<String, double>>.from(
      (baselineSnap.data()?['series'] as Map<String, dynamic>? ?? {}).map(
        (code, months) => MapEntry(
          code,
          Map<String, double>.from(
            (months as Map).map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            ),
          ),
        ),
      ),
    );

    for (final e in monthTotals.entries) {
      existingSeries.putIfAbsent(e.key, () => {})[ym] = e.value;
    }

    await baselineRef.set({
      'series': existingSeries,
      'last_snapshot_at': FieldValue.serverTimestamp(),
      'last_snapshot_month': ym,
      'last_snapshot_by': actorName,
      'source_note': 'month_end_count_$ym',
    }, SetOptions(merge: true));

    double inkTotal = 0;
    double binderTotal = 0;
    const pressInk = ['yellow', 'red', 'blue', 'black'];
    for (final code in pressInk) {
      for (final v in existingSeries[code]?.values ?? const <double>[]) {
        if (v > 0) inkTotal += v;
      }
    }
    for (final v in existingSeries['gravure_binder']?.values ?? const <double>[]) {
      if (v > 0) binderTotal += v;
    }
    final ratio = inkTotal > 0 && binderTotal > 0 ? binderTotal / inkTotal : null;

    await _db.collection(Collections.inkSettings).doc('manufacturing_config').set({
      if (ratio != null) 'binder_per_ink_kg': ratio,
      'ratio_source': ratio != null ? 'monthly_snapshots' : 'fallback',
      'ratio_updated_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Corrects [original] using the reversing-entry model: the original is marked
  /// `voided` (preserved for audit, excluded from replay) and the [correction]
  /// transaction is appended. The server re-replays and recomputes balance/WAC.
  Future<void> correctTransaction({
    required InkTransaction original,
    required InkTransaction correction,
  }) async {
    if (original.id == null) return;
    await _db.collection(Collections.inkTransactions).doc(original.id).set({
      'voided': true,
      'related_transaction_id': correction.idempotencyKey,
    }, SetOptions(merge: true));
    await recordTransaction(correction);
  }

  /// An item's full ledger, oldest-effective first. Equality query (auto-indexed)
  /// + in-memory sort, so it works without the composite index too.
  Stream<List<InkTransaction>> watchItemLedger(String itemCode) => _db
      .collection(Collections.inkTransactions)
      .where('stock_item_code', isEqualTo: itemCode)
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkTransaction.fromFirestore).toList()
          ..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
        return list;
      });

  /// Recent ledger lines for operators (qty audit only) — bounded read.
  Stream<List<InkTransaction>> watchItemLedgerRecent(
    String itemCode, {
    int limit = 20,
  }) =>
      _db
          .collection(Collections.inkTransactions)
          .where('stock_item_code', isEqualTo: itemCode)
          .orderBy('effective_at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(InkTransaction.fromFirestore).toList());

  static DateTime _meterPointReadingsSince() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 45));
  }

  /// Every transaction in the current reporting month (for the month-end report,
  /// which rolls the ledger forward per item). Bounded to the current month so
  /// the stream doesn't grow unboundedly as the ledger accumulates over time.
  Stream<List<InkTransaction>> watchAllTransactions() {
    final now = DateTime.now();
    final monthStart =
        Timestamp.fromDate(DateTime(now.year, now.month, 1));
    return _db
        .collection(Collections.inkTransactions)
        .where('effective_at', isGreaterThanOrEqualTo: monthStart)
        .snapshots()
        .map((s) => s.docs.map(InkTransaction.fromFirestore).toList());
  }

  /// Transactions effective on/after [from] — used by the month-end report when
  /// the period's opening count carries a WAC/value snapshot, so the report
  /// replays only from the last count instead of the whole ledger history. The
  /// window is bounded by the count cadence (~one period), not genesis.
  Stream<List<InkTransaction>> watchTransactionsSince(DateTime from) => _db
      .collection(Collections.inkTransactions)
      .where('effective_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map((s) => s.docs.map(InkTransaction.fromFirestore).toList());

  /// Manager "pending costs" queue — receipts awaiting a cost.
  /// Ordered by recorded_at DESC (matches existing composite index) with a cap
  /// of 50 so the stream doesn't scan the full ledger history.
  Stream<List<InkTransaction>> watchPendingCosts() => _db
      .collection(Collections.inkTransactions)
      .where('cost_status', isEqualTo: InkCostStatus.pending.value)
      .orderBy('recorded_at', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(InkTransaction.fromFirestore).toList());

  /// Manager review queue — flagged (e.g. negative-balance) movements.
  /// Ordered by recorded_at DESC (matches existing composite index) with a cap
  /// of 50 so the stream doesn't scan the full ledger history.
  Stream<List<InkTransaction>> watchFlagged() => _db
      .collection(Collections.inkTransactions)
      .where('flagged_for_review', isEqualTo: true)
      .orderBy('recorded_at', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(InkTransaction.fromFirestore).toList());

  // ---------------------------------------------------------------------------
  // OTHER METERS (report-only capture — factory toloul meters, no stock impact)
  // ---------------------------------------------------------------------------

  Future<void> writeOtherMeterLog({
    required String label,
    required double reading,
    required DateTime readingDate,
    String? actorClockNo,
    String? actorName,
    String? notes,
  }) {
    final minuteKey = readingDate.millisecondsSinceEpoch ~/ 60000;
    final safeLabel = label.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final docId = '${actorClockNo ?? 'anon'}_${safeLabel}_$minuteKey';
    return _db.collection(Collections.inkOtherMeterLogs).doc(docId).set({
      'label': label,
      'reading': reading,
      'reading_date': Timestamp.fromDate(readingDate),
      if (actorClockNo != null) 'actor_clock_no': actorClockNo,
      if (actorName != null) 'actor_name': actorName,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'recorded_at': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // SUPPLIERS (manager-curated managed list)
  // ---------------------------------------------------------------------------

  Stream<List<InkSupplier>> watchSuppliers({bool activeOnly = true}) => _db
      .collection(Collections.inkSuppliers)
      .snapshots()
      .map((s) {
        final all = s.docs.map(InkSupplier.fromFirestore).toList();
        final filtered = activeOnly ? all.where((x) => x.active).toList() : all;
        filtered.sort((a, b) {
          final c = a.sortOrder.compareTo(b.sortOrder);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return filtered;
      });

  Future<void> addSupplier(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _db
        .collection(Collections.inkSuppliers)
        .add(InkSupplier(name: trimmed, sortOrder: 99).toFirestore());
  }

  Future<void> setSupplierActive(String id, bool active) => _db
      .collection(Collections.inkSuppliers)
      .doc(id)
      .update({'active': active});

  // ---------------------------------------------------------------------------
  // CONVERSION FACTORS (litres → kg per meter-read item; manager-managed)
  // ---------------------------------------------------------------------------

  Stream<Map<String, InkConversionFactor>> watchConversionFactors() => _db
      .collection(Collections.inkConversionFactors)
      .snapshots()
      .map((s) => {
            for (final d in s.docs) d.id: InkConversionFactor.fromFirestore(d)
          });

  Future<void> saveConversionFactor(String itemCode, double kgPerLitre) => _db
      .collection(Collections.inkConversionFactors)
      .doc(itemCode)
      .set(
        InkConversionFactor(itemCode: itemCode, kgPerLitre: kgPerLitre)
            .toFirestore(),
        SetOptions(merge: true),
      );

  /// Latest cumulative meter value per item (from `consumption_meter` txns), so
  /// the meter screen can compute the next reading's delta. Bounded to the last
  /// 180 days — any item without a reading in 6 months is effectively dormant.
  Stream<Map<String, double>> watchLatestMeterReadings() {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 180)),
    );
    return _db
        .collection(Collections.inkTransactions)
        .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
        .where('effective_at', isGreaterThanOrEqualTo: cutoff)
        .snapshots()
        .map((s) {
          final latest = <String, ({DateTime at, double reading})>{};
          for (final doc in s.docs) {
            final t = InkTransaction.fromFirestore(doc);
            if (t.meterReading == null) continue;
            final cur = latest[t.stockItemCode];
            if (cur == null || t.effectiveAt.isAfter(cur.at)) {
              latest[t.stockItemCode] =
                  (at: t.effectiveAt, reading: t.meterReading!);
            }
          }
          return {for (final e in latest.entries) e.key: e.value.reading};
        });
  }

  /// The most recent [limit] meter readings per item (newest first) — for the
  /// grid view that shows the previous few days alongside the entry field.
  /// Bounded to the last 90 days so the stream doesn't scan the full ledger.
  Stream<Map<String, List<({DateTime at, double reading})>>>
      watchRecentMeterReadings({int limit = 4}) {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 90)),
    );
    return _db
        .collection(Collections.inkTransactions)
        .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
        .where('effective_at', isGreaterThanOrEqualTo: cutoff)
        .snapshots()
        .map((s) {
          final byItem = <String, List<({DateTime at, double reading})>>{};
          for (final doc in s.docs) {
            final t = InkTransaction.fromFirestore(doc);
            if (t.meterReading == null) continue;
            (byItem[t.stockItemCode] ??= [])
                .add((at: t.effectiveAt, reading: t.meterReading!));
          }
          for (final key in byItem.keys.toList()) {
            final list = byItem[key]!
              ..sort((a, b) => b.at.compareTo(a.at)); // newest first
            if (list.length > limit) byItem[key] = list.sublist(0, limit);
          }
          return byItem;
        });
  }

  // ---------------------------------------------------------------------------
  // RECIPES + PRODUCTION
  // ---------------------------------------------------------------------------

  Stream<List<InkRecipe>> watchRecipes({bool activeOnly = true}) => _db
      .collection(Collections.inkRecipes)
      .snapshots()
      .map((s) {
        final all = s.docs.map(InkRecipe.fromFirestore).toList();
        final filtered = activeOnly ? all.where((r) => r.active).toList() : all;
        filtered
            .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return filtered;
      });

  Future<void> saveRecipe(InkRecipe recipe) async {
    _guardWrite();
    if (recipe.id == null) {
      await _db.collection(Collections.inkRecipes).add(recipe.toFirestore());
    } else {
      // Bump the version on every edit (recipe history is preserved on runs,
      // which snapshot recipe_version at production time).
      await _db.collection(Collections.inkRecipes).doc(recipe.id).set(
            recipe.copyWith(version: recipe.version + 1).toFirestore(),
            SetOptions(merge: true),
          );
    }
  }

  Future<void> setRecipeActive(String id, bool active) =>
      _db.collection(Collections.inkRecipes).doc(id).update({'active': active});

  Stream<List<InkProductionRun>> watchProductionRuns() => _db
      .collection(Collections.inkProductionRuns)
      .snapshots()
      .map((s) {
        final l = s.docs.map(InkProductionRun.fromFirestore).toList()
          ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
        return l;
      });

  /// Recent toloul recovery transactions (newest-first, non-voided).
  Stream<List<InkTransaction>> watchRecentRecoveries({int limit = 15}) => _db
      .collection(Collections.inkTransactions)
      .where('type', isEqualTo: InkTxnType.recovery.value)
      .snapshots()
      .map((s) {
        final l = s.docs
            .map(InkTransaction.fromFirestore)
            .where((t) => !t.voided)
            .toList()
          ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
        return l.take(limit).toList();
      });

  /// Records a production run: a `consumption_production` txn per input (valued
  /// at current WAC) and one `manufacture` txn for the output whose total_cost
  /// is the summed input cost (matches the legacy month-end model). All share a
  /// productionRunId. Returns the run id.
  Future<String> recordProductionRun({
    required InkRecipe recipe,
    required int pots,
    required DateTime effectiveAt,
    required String actorClockNo,
    required String actorName,
    required Map<String, double> wacByItem,
  }) async {
    _guardWrite();
    final runId = _uuid.v4();
    var totalInputCost = 0.0;
    final inputTxns = <InkTransaction>[];
    for (var i = 0; i < recipe.inputs.length; i++) {
      final line = recipe.inputs[i];
      final qty = line.qtyPerPot * pots;
      totalInputCost += qty * (wacByItem[line.itemCode] ?? 0);
      inputTxns.add(InkTransaction(
        type: InkTxnType.consumptionProduction,
        stockItemCode: line.itemCode,
        quantityDelta: -qty,
        effectiveAt: effectiveAt,
        costStatus: InkCostStatus.na,
        productionRunId: runId,
        actorClockNo: actorClockNo,
        actorName: actorName,
        idempotencyKey: '${runId}_in_$i',
      ));
    }
    final outputQty = recipe.outputPerPot * pots;
    final outputTxn = InkTransaction(
      type: InkTxnType.manufacture,
      stockItemCode: recipe.outputItemCode,
      quantityDelta: outputQty,
      totalCost: totalInputCost,
      effectiveAt: effectiveAt,
      costStatus: InkCostStatus.costed,
      productionRunId: runId,
      actorClockNo: actorClockNo,
      actorName: actorName,
      idempotencyKey: '${runId}_out',
    );

    await _db.collection(Collections.inkProductionRuns).doc(runId).set({
      'recipe_id': recipe.id,
      'recipe_name': recipe.name,
      'recipe_version': recipe.version,
      'output_item_code': recipe.outputItemCode,
      'pots': pots,
      'output_qty': outputQty,
      'total_input_cost': totalInputCost,
      'effective_at': Timestamp.fromDate(effectiveAt),
      'actor_clock_no': actorClockNo,
      'actor_name': actorName,
      'recorded_at': FieldValue.serverTimestamp(),
      ...personaAuditFields(),
    });
    for (final t in inputTxns) {
      await recordTransaction(t);
    }
    await recordTransaction(outputTxn);
    return runId;
  }

  /// Voids an entire production run: marks the run doc and EVERY linked
  /// transaction (the consumption_production inputs + the manufacture output)
  /// voided so the replay reverses the whole batch. Atomic (single batch); the
  /// server re-replays each affected stock item. Preserved for audit (the rows
  /// are flagged, never deleted). The caller must already have cleared the
  /// closed-period guard for [InkProductionRun.effectiveAt].
  Future<void> voidProductionRun(
    String runId, {
    required String reason,
    required String actorClockNo,
    required String actorName,
  }) async {
    final txnsSnap = await _db
        .collection(Collections.inkTransactions)
        .where('production_run_id', isEqualTo: runId)
        .get();
    final batch = _db.batch();
    final voidMeta = {
      'voided': true,
      'void_reason': reason,
      'voided_by_clock_no': actorClockNo,
      'voided_by_name': actorName,
      'voided_at': FieldValue.serverTimestamp(),
    };
    for (final d in txnsSnap.docs) {
      batch.set(d.reference, voidMeta, SetOptions(merge: true));
    }
    batch.set(
      _db.collection(Collections.inkProductionRuns).doc(runId),
      {
        'voided': true,
        'void_reason': reason,
        'voided_by_name': actorName,
        'voided_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // IBCs (ink received in containers)
  // ---------------------------------------------------------------------------

  Stream<List<InkIbc>> watchIbcs({InkIbcStatus? status}) => _db
      .collection(Collections.inkIbcs)
      .snapshots()
      .map((s) {
        final list = <InkIbc>[];
        for (final doc in s.docs) {
          final ibc = InkIbc.tryFromFirestore(doc);
          if (ibc != null) {
            list.add(ibc);
          } else {
            assert(() {
              debugPrint('Skipping unparseable ink_ibcs/${doc.id}');
              return true;
            }());
          }
        }
        var filtered = list;
        if (status != null) {
          filtered = list.where((i) => i.status == status).toList();
        }
        filtered.sort((a, b) => b.receivedDate.compareTo(a.receivedDate));
        return filtered;
      });

  /// Open shipments (status awaiting_receipt / receiving) for a packaging mode
  /// the operator can receive against. Created + costed in Pulse; read-only here.
  Stream<List<InkShipment>> _watchOpenShipments(String mode) => _db
      .collection(Collections.inkShipments)
      .where('packaging_mode', isEqualTo: mode)
      .where('status', whereIn: ['awaiting_receipt', 'receiving'])
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkShipment.fromFirestore).toList();
        list.sort((a, b) => a.id.compareTo(b.id));
        return list;
      });

  /// Open IBC shipments (inks, per-serial receiving).
  Stream<List<InkShipment>> watchOpenIbcShipments() =>
      _watchOpenShipments('ibc');

  /// Open pallet shipments (raw materials, aggregate-tally receiving).
  Stream<List<InkShipment>> watchOpenPalletShipments() =>
      _watchOpenShipments('pallet');

  /// Sent / partially fulfilled POs for linking local raw-material receipts.
  Stream<List<InkPurchaseOrder>> watchOpenPurchaseOrders() => _db
      .collection(Collections.inkPurchaseOrders)
      .where('status', whereIn: ['sent', 'partially_fulfilled'])
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkPurchaseOrder.fromFirestore).toList();
        list.sort((a, b) => b.pulseRef.compareTo(a.pulseRef));
        return list;
      });

  static DateTime _calendarDayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _calendarDayEnd(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  /// Throws if a non-voided `consumption_meter` session exists on [date]'s
  /// calendar day — operators must void the existing session before re-submitting.
  Future<void> assertNoActiveMeterSessionForCalendarDay(DateTime date) async {
    final dayStart = _calendarDayStart(date);
    final dayEnd = _calendarDayEnd(date);
    final snap = await _db
        .collection(Collections.inkTransactions)
        .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
        .where('effective_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('effective_at', isLessThanOrEqualTo: Timestamp.fromDate(dayEnd))
        .get();
    final hasActive = snap.docs.any(
      (d) => !(d.data()['voided'] as bool? ?? false),
    );
    if (hasActive) {
      throw StateError(
        'A meter reading session already exists for this calendar day. '
        'Void it first before submitting again.',
      );
    }
  }

  /// Deduct receipt qty from PO remaining; idempotent per [receiptKey].
  Future<void> applyReceiptToPurchaseOrder({
    required String purchaseOrderId,
    required String itemCode,
    required double quantity,
    required String receiptKey,
  }) async {
    if (purchaseOrderId.isEmpty || quantity <= 0 || receiptKey.isEmpty) return;

    final poRef =
        _db.collection(Collections.inkPurchaseOrders).doc(purchaseOrderId);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(poRef);
      if (!snap.exists) {
        throw StateError('Purchase order $purchaseOrderId not found');
      }
      final d = snap.data() ?? {};
      final applied = (d['applied_receipt_keys'] as List?)?.cast<String>() ?? [];
      if (applied.contains(receiptKey)) return;

      final po = InkPurchaseOrder.fromFirestore(snap);
      final result = deductReceiptFromPurchaseOrder(
        remainingKgByItem: po.remainingKgByItem,
        itemCode: itemCode,
        quantity: quantity,
      );

      txn.set(
        poRef,
        {
          'remaining_kg_by_item': result.remainingKgByItem,
          'status': result.status,
          'applied_receipt_keys': FieldValue.arrayUnion([receiptKey]),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Deducts shipment manifest lines from PO remaining qty; idempotent per
  /// shipment via `fulfillment_applied_at`. Called on mobile IBC receive, not
  /// on Pulse shipment create.
  Future<void> applyShipmentToPurchaseOrder({
    required InkShipment shipment,
    required String purchaseOrderId,
    required Map<String, double> receivedKgByItem,
  }) async {
    if (purchaseOrderId.isEmpty) return;

    final poRef =
        _db.collection(Collections.inkPurchaseOrders).doc(purchaseOrderId);
    final shipRef = _db.collection(Collections.inkShipments).doc(shipment.id);

    await _db.runTransaction((txn) async {
      final poSnap = await txn.get(poRef);
      if (!poSnap.exists) {
        throw StateError('Purchase order $purchaseOrderId not found');
      }

      final shipSnap = await txn.get(shipRef);
      if (shipSnap.exists) {
        final applied = shipSnap.data()?['fulfillment_applied_at'];
        if (applied != null) return;
      }

      final poData = poSnap.data() ?? {};
      final remainingRaw =
          poData['remaining_kg_by_item'] as Map<String, dynamic>? ?? {};
      final remaining = <String, double>{
        for (final e in remainingRaw.entries)
          e.key: (e.value as num?)?.toDouble() ?? 0,
      };
      final linked =
          (poData['linked_shipment_ids'] as List?)?.cast<String>() ?? [];

      final result = applyShipmentDeduction(
        remainingKgByItem: remaining,
        receivedKgByItem: receivedKgByItem,
        linkedShipmentIds: linked,
        shipmentId: shipment.id,
      );

      txn.set(
        poRef,
        {
          'remaining_kg_by_item': result.remainingKgByItem,
          'linked_shipment_ids': result.linkedShipmentIds,
          'status': result.status,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      txn.set(
        shipRef,
        {
          'purchase_order_id': purchaseOrderId,
          'fulfillment_applied_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Receiving ink via IBC — Wave B: `ink_ibcs` creates go through the
  /// `recordInkIbcReceipt` Cloud Function (Admin SDK). Purchase txns + shipment
  /// updates are written in the same CF transaction.
  Future<void> recordIbcReceipt({
    required List<InkIbc> ibcs,
    required String supplierName,
    required DateTime effectiveAt,
    required String actorClockNo,
    required String actorName,
    String? orderNumber,
    String? cgnaNumber,
    String? shipmentId,
  }) async {
    _guardWrite();
    final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
        .httpsCallable('recordInkIbcReceipt');
    await callable.call<Map<String, dynamic>>({
      'ibcs': [
        for (final ibc in ibcs)
          {
            'sscc': ibc.sscc,
            'ibc_number': ibc.ibcNumber,
            'item_code': ibc.itemCode,
            'kg': ibc.kg,
            'charge_number': ibc.chargeNumber,
          },
      ],
      'supplier_name': supplierName,
      'effective_at': effectiveAt.toIso8601String(),
      'actor_clock_no': actorClockNo,
      'actor_name': actorName,
      if (orderNumber != null && orderNumber.isNotEmpty)
        'order_number': orderNumber,
      if (cgnaNumber != null && cgnaNumber.isNotEmpty) 'cgna_number': cgnaNumber,
      if (shipmentId != null && shipmentId.isNotEmpty) 'shipment_id': shipmentId,
    });
  }

  /// Receiving a raw material / solvent (one item per call). Records the
  /// cost-pending `purchase` and, when [shipmentId] is given, stamps it and
  /// appends an aggregate received line to the pallet shipment (status →
  /// receiving — pallet shipments carry several items, each received separately).
  /// When [purchaseOrderId] is given, deducts [remaining_kg_by_item] on the PO
  /// (local-loop fulfillment; idempotent via txn idempotency key).
  Future<void> recordRawMaterialReceipt({
    required InkTransaction txn,
    String? shipmentId,
    String? purchaseOrderId,
  }) async {
    await recordTransaction(txn);
    if (shipmentId != null && shipmentId.isNotEmpty) {
      await _db.collection(Collections.inkShipments).doc(shipmentId).set({
        'received_units': FieldValue.arrayUnion([
          {
            'ref': 'bulk:${txn.stockItemCode}',
            'item_code': txn.stockItemCode,
            'net_kg': txn.quantityDelta,
            'scanned_by': txn.actorClockNo,
            'scanned_at': Timestamp.fromDate(txn.effectiveAt),
          }
        ]),
        'status': 'receiving',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (purchaseOrderId != null && purchaseOrderId.isNotEmpty) {
      await applyReceiptToPurchaseOrder(
        purchaseOrderId: purchaseOrderId,
        itemCode: txn.stockItemCode,
        quantity: txn.quantityDelta,
        receiptKey: txn.idempotencyKey,
      );
    }
  }

  /// Transfers an IBC to a tank: marks it transferred and records the toloul
  /// used to wash it as a `consumption_toloul_wash` (ink stock is unaffected —
  /// the ink was already counted at receipt).
  ///
  /// Uses a Firestore transaction so both writes are atomic and idempotent:
  /// the wash transaction doc is only created if it doesn't already exist,
  /// preventing a permission-denied error when retrying a partial failure.
  ///
  /// If [markDamaged] is true (operator identified the IBC as damaged at
  /// consume time), the IBC still transfers normally in the ink ledger, but
  /// is excluded from waste stock entirely — [damageReason] is required in
  /// that case and is recorded on the `ink_ibcs` doc.
  Future<void> transferIbc({
    required InkIbc ibc,
    required String tolulItemCode,
    required double washLitres,
    required DateTime effectiveAt,
    required String actorClockNo,
    required String actorName,
    bool markDamaged = false,
    String? damageReason,
  }) async {
    _guardWrite();
    assert(!markDamaged || (damageReason != null && damageReason.trim().isNotEmpty),
        'damageReason is required when markDamaged is true');
    final ibcRef = _db.collection(Collections.inkIbcs).doc(ibc.ibcNumber);
    final washKey = 'ibcwash_${ibc.ibcNumber}';
    final washRef = _db.collection(Collections.inkTransactions).doc(washKey);

    await _db.runTransaction((txn) async {
      // Firestore requires every read before any write in a transaction.
      // Idempotency guard: the old deterministic-doc-id waste_stock scheme
      // gave this for free; the shared pool model needs it explicit here.
      final ibcSnap = await txn.get(ibcRef);
      final ibcData = ibcSnap.data();
      final alreadyTransferred =
          InkIbcStatus.fromValue(ibcData?['status'] as String?) ==
              InkIbcStatus.transferred;
      final alreadyDamaged = ibcData?['damage_flag'] == true;
      if (alreadyTransferred || alreadyDamaged) return;

      final washSnap = washLitres > 0 ? await txn.get(washRef) : null;
      final transferredAt = Timestamp.fromDate(effectiveAt);

      final IbcPoolRead? poolRead = markDamaged
          ? null
          : await WasteStockCrosslink.readIbcPool(txn: txn, db: _db);

      if (markDamaged) {
        txn.set(
          ibcRef,
          {
            'status': InkIbcStatus.transferred.value,
            'transferred_date': transferredAt,
            'wash_toloul_litres': washLitres,
            'damage_flag': true,
            'damage_reason': damageReason,
            'damage_recorded_at': transferredAt,
            'damage_recorded_by': actorClockNo,
          },
          SetOptions(merge: true),
        );
      } else {
        WasteStockCrosslink.applyIbcPoolConsume(
          txn: txn,
          db: _db,
          pool: poolRead!,
          ibcNumber: ibc.ibcNumber,
          actorClockNo: actorClockNo,
          actorName: actorName,
          createdAt: transferredAt,
        );
        txn.set(
          ibcRef,
          {
            'status': InkIbcStatus.transferred.value,
            'transferred_date': transferredAt,
            'wash_toloul_litres': washLitres,
          },
          SetOptions(merge: true),
        );
      }

      if (washSnap != null && !washSnap.exists) {
        txn.set(
          washRef,
          InkTransaction(
            type: InkTxnType.consumptionTolulWash,
            stockItemCode: tolulItemCode,
            quantityDelta: -washLitres,
            effectiveAt: effectiveAt,
            costStatus: InkCostStatus.na,
            ibcNumber: ibc.ibcNumber,
            actorClockNo: actorClockNo,
            actorName: actorName,
            idempotencyKey: washKey,
          ).toFirestore(),
        );
      }
    });
  }

  /// Voids an IBC transfer (consumption): returns the IBC to `received` and voids
  /// its linked `consumption_toloul_wash` transaction so the wash toloul is added
  /// back to stock on replay. Atomic batch; the wash row is flagged (not deleted)
  /// for audit. The caller must already have cleared the closed-period guard for
  /// the transfer date.
  Future<void> voidIbcTransfer(
    InkIbc ibc, {
    required String reason,
    required String actorClockNo,
    required String actorName,
  }) async {
    _guardWrite();
    await WasteStockCrosslink.assertIbcStockVoidable(_db, ibc.ibcNumber);

    final washRef =
        _db.collection(Collections.inkTransactions).doc('ibcwash_${ibc.ibcNumber}');
    final washSnap = await washRef.get();
    final batch = _db.batch();
    final now = Timestamp.now();
    if (washSnap.exists) {
      batch.set(
        washRef,
        {
          'voided': true,
          'void_reason': reason,
          'voided_by_clock_no': actorClockNo,
          'voided_by_name': actorName,
          'voided_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    batch.set(
      _db.collection(Collections.inkIbcs).doc(ibc.ibcNumber),
      {
        'status': InkIbcStatus.received.value,
        'transferred_date': FieldValue.delete(),
        'wash_toloul_litres': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
    await WasteStockCrosslink.disposeIbcStockOnVoid(
      batch: batch,
      db: _db,
      ibcNumber: ibc.ibcNumber,
      updatedAt: now,
    );
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // METER POINTS (aux toloul meters — recovery/usage; NO stock impact)
  // ---------------------------------------------------------------------------

  Stream<List<InkMeterPoint>> watchMeterPoints({bool activeOnly = true}) => _db
      .collection(Collections.inkMeterPoints)
      .snapshots()
      .map((s) {
        final all = s.docs.map(InkMeterPoint.fromFirestore).toList();
        final f = activeOnly ? all.where((p) => p.active).toList() : all;
        f.sort((a, b) {
          final c = a.sortOrder.compareTo(b.sortOrder);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return f;
      });

  Future<void> addMeterPoint(String name, String linkage) async {
    final t = name.trim();
    if (t.isEmpty) return;
    await _db.collection(Collections.inkMeterPoints).add(
        InkMeterPoint(name: t, linkage: linkage, sortOrder: 99).toFirestore());
  }

  Future<void> setMeterPointActive(String id, bool active) => _db
      .collection(Collections.inkMeterPoints)
      .doc(id)
      .update({'active': active});

  /// Records meter-point readings (no stock effect). Each line carries the
  /// already-computed [consumption] (delta or reset value).
  /// When [sessionId] is given, doc id is `${sessionId}_${pointId}` and
  /// readings are linked for void-by-session.
  Future<void> recordMeterPointReadings({
    required DateTime readingDate,
    required List<
            ({String pointId, double reading, double consumption, bool reset})>
        lines,
    required String actorClockNo,
    required String actorName,
    String? sessionId,
  }) async {
    for (final l in lines) {
      final docId = sessionId != null && sessionId.isNotEmpty
          ? '${sessionId}_${l.pointId}'
          : '${l.pointId}_${readingDate.millisecondsSinceEpoch ~/ 60000}';
      await _db.collection(Collections.inkMeterPointReadings).doc(docId).set({
        'point_id': l.pointId,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        'reading': l.reading,
        'consumption': l.consumption,
        'reset': l.reset,
        'reading_date': Timestamp.fromDate(readingDate),
        'recorded_at': FieldValue.serverTimestamp(),
        'actor_clock_no': actorClockNo,
        'actor_name': actorName,
      });
    }
  }

  /// Throws when any [pointIds] already have a reading on [date]'s calendar day.
  Future<void> assertToloulPointsAvailableForCalendarDay({
    required DateTime date,
    required List<String> pointIds,
  }) async {
    if (pointIds.isEmpty) return;
    final captured = await watchTodayToloulPointIds(onDate: date).first;
    final dupes = pointIds.where(captured.contains).toList();
    if (dupes.isNotEmpty) {
      throw StateError(
        'Toloul meter reading(s) already captured today for: ${dupes.join(', ')}. '
        'Void the existing session first if you need to replace them.',
      );
    }
  }

  /// Atomic daily submit: ink `consumption_meter` rows + toloul meter-point
  /// readings in one batch, sharing [sessionId]. Blocks duplicate ink sessions
  /// per calendar day; toloul-only follow-up submits are allowed for points not
  /// yet captured that day.
  Future<void> recordDailyMeterSession({
    required String sessionId,
    required DateTime readingDate,
    required List<InkTransaction> inkTransactions,
    required List<
            ({
              String pointId,
              double reading,
              double consumption,
              bool reset,
              bool noChange,
            })>
        toloulLines,
    required String actorClockNo,
    required String actorName,
  }) async {
    _guardWrite();
    if (inkTransactions.isNotEmpty) {
      await assertNoActiveMeterSessionForCalendarDay(readingDate);
    }
    if (toloulLines.isNotEmpty) {
      await assertToloulPointsAvailableForCalendarDay(
        date: readingDate,
        pointIds: toloulLines.map((l) => l.pointId).toList(),
      );
    }

    final batch = _db.batch();
    for (final t in inkTransactions) {
      final key = t.idempotencyKey.isNotEmpty
          ? t.idempotencyKey
          : '${sessionId}_${t.stockItemCode}';
      batch.set(
        _db.collection(Collections.inkTransactions).doc(key),
        InkTransaction(
          id: t.id,
          seqNumber: t.seqNumber,
          type: t.type,
          stockItemCode: t.stockItemCode,
          quantityDelta: t.quantityDelta,
          effectiveAt: t.effectiveAt,
          recordedAt: t.recordedAt,
          totalCost: t.totalCost,
          newWac: t.newWac,
          costStatus: t.costStatus,
          voided: t.voided,
          balanceBefore: t.balanceBefore,
          balanceAfter: t.balanceAfter,
          wacAtTime: t.wacAtTime,
          actorClockNo: t.actorClockNo,
          actorName: t.actorName,
          idempotencyKey: key,
          flaggedForReview: t.flaggedForReview,
          flagReason: t.flagReason,
          reason: t.reason,
          notes: t.notes,
          relatedTransactionId: t.relatedTransactionId,
          productionRunId: t.productionRunId,
          sessionId: sessionId,
          ibcNumber: t.ibcNumber,
          lurgiSource: t.lurgiSource,
          supplierName: t.supplierName,
          litresEntered: t.litresEntered,
          conversionFactorUsed: t.conversionFactorUsed,
          meterReading: t.meterReading,
          readingDate: t.readingDate,
          shipmentId: t.shipmentId,
          purchaseOrderId: t.purchaseOrderId,
        ).toFirestore(),
      );
    }
    for (final l in toloulLines) {
      final docId = '${sessionId}_${l.pointId}';
      batch.set(
        _db.collection(Collections.inkMeterPointReadings).doc(docId),
        {
          'point_id': l.pointId,
          'session_id': sessionId,
          'reading': l.reading,
          'consumption': l.consumption,
          'reset': l.reset,
          if (l.noChange) 'notes': 'No change in meter reading',
          'reading_date': Timestamp.fromDate(readingDate),
          'recorded_at': FieldValue.serverTimestamp(),
          'actor_clock_no': actorClockNo,
          'actor_name': actorName,
        },
      );
    }
    await batch.commit();
  }

  /// The most recent [limit] readings per meter point (newest first) — for the
  /// history strip in the entry grid. Bounded to the last 45 days.
  Stream<Map<String, List<({DateTime at, double reading})>>>
      watchRecentMeterPointReadings({int limit = 4}) {
    final since = Timestamp.fromDate(_meterPointReadingsSince());
    return _db
        .collection(Collections.inkMeterPointReadings)
        .where('reading_date', isGreaterThanOrEqualTo: since)
        .snapshots()
        .map((s) {
            final byPoint = <String, List<({DateTime at, double reading})>>{};
            for (final doc in s.docs) {
              final d = doc.data();
              final pid = d['point_id'] as String?;
              if (pid == null) continue;
              final at =
                  (d['reading_date'] as Timestamp?)?.toDate() ?? DateTime(2000);
              final reading = (d['reading'] as num?)?.toDouble() ?? 0;
              (byPoint[pid] ??= []).add((at: at, reading: reading));
            }
            for (final key in byPoint.keys.toList()) {
              final list = byPoint[key]!
                ..sort((a, b) => b.at.compareTo(a.at));
              if (list.length > limit) byPoint[key] = list.sublist(0, limit);
            }
            return byPoint;
          });
  }

  /// Latest cumulative reading per meter point (for delta computation).
  /// Uses a 45-day window; daily readings always fall inside this window.
  Stream<Map<String, double>> watchLatestMeterPointReadings() {
    final since = Timestamp.fromDate(_meterPointReadingsSince());
    return _db
        .collection(Collections.inkMeterPointReadings)
        .where('reading_date', isGreaterThanOrEqualTo: since)
        .snapshots()
        .map((s) {
        final latest = <String, ({DateTime at, double reading})>{};
        for (final doc in s.docs) {
          final d = doc.data();
          final pid = d['point_id'] as String?;
          if (pid == null) continue;
          final at =
              (d['reading_date'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final reading = (d['reading'] as num?)?.toDouble() ?? 0;
          final cur = latest[pid];
          if (cur == null || at.isAfter(cur.at)) {
            latest[pid] = (at: at, reading: reading);
          }
        }
        return {for (final e in latest.entries) e.key: e.value.reading};
      });
  }

  /// Item codes with a non-voided ink meter reading captured today.
  Stream<Set<String>> watchTodayInkMeterItemCodes() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _db
        .collection(Collections.inkTransactions)
        .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
        .where('effective_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .snapshots()
        .map((s) {
          final codes = <String>{};
          for (final d in s.docs) {
            if (d.data()['voided'] as bool? ?? false) continue;
            final code = d.data()['stock_item_code'] as String?;
            if (code != null && code.isNotEmpty) codes.add(code);
          }
          return codes;
        });
  }

  /// Toloul meter point ids with a reading captured on today's calendar day.
  Stream<Set<String>> watchTodayToloulPointIds({DateTime? onDate}) {
    final anchor = onDate ?? DateTime.now();
    final dayStart = _calendarDayStart(anchor);
    final dayEnd = _calendarDayEnd(anchor);
    return _db
        .collection(Collections.inkMeterPointReadings)
        .where('reading_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('reading_date', isLessThanOrEqualTo: Timestamp.fromDate(dayEnd))
        .snapshots()
        .map((s) {
          final ids = <String>{};
          for (final d in s.docs) {
            if (d.data()['voided'] as bool? ?? false) continue;
            final pid = d.data()['point_id'] as String?;
            if (pid != null && pid.isNotEmpty) ids.add(pid);
          }
          return ids;
        });
  }

  /// Combined daily-readings status — all metered ink items AND all toloul points.
  Stream<InkDailyReadingsStatus> watchDailyReadingsStatus({
    required Set<String> requiredInkCodes,
    required Set<String> requiredToloulPointIds,
    Map<String, String> toloulPointNames = const {},
  }) {
    final controller = StreamController<InkDailyReadingsStatus>();
    Set<String> inkCaptured = {};
    Set<String> toloulCaptured = {};

    void emit() {
      final needsInk = requiredInkCodes.isNotEmpty;
      final needsToloul = requiredToloulPointIds.isNotEmpty;
      final missingToloulIds = requiredToloulPointIds
          .where((id) => !toloulCaptured.contains(id))
          .toList();
      final missingToloulNames = missingToloulIds
          .map((id) => toloulPointNames[id] ?? id)
          .toList();
      if (!controller.isClosed) {
        controller.add(InkDailyReadingsStatus(
          needsInk: needsInk,
          needsToloul: needsToloul,
          inkDone:
              !needsInk || requiredInkCodes.every(inkCaptured.contains),
          toloulDone: !needsToloul ||
              requiredToloulPointIds.every(toloulCaptured.contains),
          inkCapturedCount:
              inkCaptured.where(requiredInkCodes.contains).length,
          inkRequiredCount: requiredInkCodes.length,
          toloulCapturedCount:
              toloulCaptured.where(requiredToloulPointIds.contains).length,
          toloulRequiredCount: requiredToloulPointIds.length,
          missingToloulPointNames: missingToloulNames,
        ));
      }
    }

    final inkSub = watchTodayInkMeterItemCodes().listen((s) {
      inkCaptured = s;
      emit();
    });
    final tolSub = watchTodayToloulPointIds().listen((s) {
      toloulCaptured = s;
      emit();
    });

    controller.onCancel = () async {
      await inkSub.cancel();
      await tolSub.cancel();
    };

    return controller.stream;
  }

  /// @deprecated Use [watchDailyReadingsStatus] via [inkDailyReadingsStatusProvider].
  Stream<bool> watchTodayInkMeterStatus() =>
      watchTodayInkMeterItemCodes().map((codes) => codes.isNotEmpty);

  /// @deprecated Use [watchDailyReadingsStatus] via [inkDailyReadingsStatusProvider].
  Stream<bool> watchTodayToloulMeterStatus() =>
      watchTodayToloulPointIds().map((ids) => ids.isNotEmpty);

  /// All meter-point readings (for month-end totals).
  Stream<List<({String pointId, double consumption, DateTime readingDate})>>
      watchMeterPointReadings() => _db
          .collection(Collections.inkMeterPointReadings)
          .snapshots()
          .map((s) => s.docs.map((doc) {
                final d = doc.data();
                return (
                  pointId: d['point_id'] as String? ?? '',
                  consumption: (d['consumption'] as num?)?.toDouble() ?? 0,
                  readingDate: (d['reading_date'] as Timestamp?)?.toDate() ??
                      DateTime(2000),
                );
              }).toList());

  /// Recent ink meter-reading SESSIONS (grouped by session_id), newest first —
  /// for the void list. Each daily submit shares one session_id across its ink
  /// `consumption_meter` rows; this rolls them up so a whole session can be voided.
  Stream<List<InkMeterSession>> watchRecentMeterSessions({int days = 90}) => _db
      .collection(Collections.inkTransactions)
      .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
      .where('effective_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
              DateTime.now().subtract(Duration(days: days))))
      .snapshots()
      .map((s) {
        final bySession = <String, InkMeterSession>{};
        for (final doc in s.docs) {
          final d = doc.data();
          final sid = d['session_id'] as String?;
          if (sid == null || sid.isEmpty) continue;
          final date = (d['reading_date'] as Timestamp?)?.toDate() ??
              (d['effective_at'] as Timestamp?)?.toDate() ??
              DateTime(2000);
          final voided = d['voided'] as bool? ?? false;
          final cur = bySession[sid];
          if (cur == null) {
            bySession[sid] = InkMeterSession(
              sessionId: sid,
              readingDate: date,
              actorName: d['actor_name'] as String? ?? '',
              itemCount: 1,
              allVoided: voided,
            );
          } else {
            bySession[sid] = cur.copyWith(
              itemCount: cur.itemCount + 1,
              allVoided: cur.allVoided && voided,
            );
          }
        }
        final list = bySession.values.toList()
          ..sort((a, b) => b.readingDate.compareTo(a.readingDate));
        return list;
      });

  /// Voids a whole meter-reading session: flags every ink `consumption_meter`
  /// row with [sessionId] voided (preserved for audit; the server re-replays so
  /// the stock is restored) and DELETES linked toloul meter-point readings
  /// (matched by [sessionId]; aux data with no stock impact — removed so the
  /// operator can re-enter the session). The caller must already have cleared
  /// the closed-period guard for [readingDate].
  Future<void> voidMeterSession(
    String sessionId,
    DateTime readingDate, {
    required String reason,
    required String actorClockNo,
    required String actorName,
  }) async {
    // A meter session's id is unique to its consumption_meter rows, so an
    // equality on session_id alone is correct (and needs no composite index).
    final txnsSnap = await _db
        .collection(Collections.inkTransactions)
        .where('session_id', isEqualTo: sessionId)
        .get();
    final tolSnap = await _db
        .collection(Collections.inkMeterPointReadings)
        .where('session_id', isEqualTo: sessionId)
        .get();
    final batch = _db.batch();
    for (final d in txnsSnap.docs) {
      batch.set(
        d.reference,
        {
          'voided': true,
          'void_reason': reason,
          'voided_by_clock_no': actorClockNo,
          'voided_by_name': actorName,
          'voided_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    for (final d in tolSnap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}

/// A rolled-up ink meter-reading session (one daily submit) for the void list.
class InkMeterSession {
  const InkMeterSession({
    required this.sessionId,
    required this.readingDate,
    required this.actorName,
    required this.itemCount,
    required this.allVoided,
  });

  final String sessionId;
  final DateTime readingDate;
  final String actorName;
  final int itemCount;
  final bool allVoided;

  InkMeterSession copyWith({int? itemCount, bool? allVoided}) => InkMeterSession(
        sessionId: sessionId,
        readingDate: readingDate,
        actorName: actorName,
        itemCount: itemCount ?? this.itemCount,
        allVoided: allVoided ?? this.allVoided,
      );
}
