import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/ink_conversion_factor.dart';
import '../models/ink_ibc.dart';
import '../models/ink_meter_point.dart';
import '../models/ink_production_run.dart';
import '../models/ink_recipe.dart';
import '../models/ink_settings.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_supplier.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';

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

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------

  Stream<InkSettings> watchSettings() => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .snapshots()
      .map((s) => s.exists ? InkSettings.fromFirestore(s) : InkSettings.defaults);

  Future<void> saveSettings(InkSettings settings) => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(settings.toFirestore(), SetOptions(merge: true));

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
  Future<void> recordTransaction(InkTransaction txn) async {
    final key =
        txn.idempotencyKey.isNotEmpty ? txn.idempotencyKey : _uuid.v4();
    await _db
        .collection(Collections.inkTransactions)
        .doc(key)
        .set(txn.toFirestore());
  }

  /// Manager: enter/correct the cost on a pending receipt → flips to `costed`
  /// and triggers a WAC re-replay server-side.
  Future<void> setPurchaseCost(String txnId, double totalCost) => _db
      .collection(Collections.inkTransactions)
      .doc(txnId)
      .update({'total_cost': totalCost, 'cost_status': InkCostStatus.costed.value});

  /// Records a month-end count on a designated [countDate] (which need not be
  /// the calendar month-end). For each item whose physical count differs from
  /// the ledger balance, writes an `adjustment` for the delta (count − ledger),
  /// at the current WAC — i.e. the adjustment is computed automatically from the
  /// month's runs, exactly as the factory does it manually today. All
  /// adjustments share a sessionId.
  Future<void> recordMonthEndCount({
    required DateTime countDate,
    required List<({String itemCode, double counted, double ledgerBalance})>
        lines,
    required String actorClockNo,
    required String actorName,
  }) async {
    final sessionId = _uuid.v4();
    for (final l in lines) {
      final delta = l.counted - l.ledgerBalance;
      if (delta.abs() < 1e-9) continue; // count matches ledger — no adjustment
      await recordTransaction(InkTransaction(
        type: InkTxnType.adjustment,
        stockItemCode: l.itemCode,
        quantityDelta: delta,
        effectiveAt: countDate,
        costStatus: InkCostStatus.na,
        reason: 'Month-end count',
        sessionId: sessionId,
        actorClockNo: actorClockNo,
        actorName: actorName,
        idempotencyKey: '${sessionId}_adj_${l.itemCode}',
      ));
    }
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

  /// Every transaction (for the month-end report, which rolls the ledger
  /// forward per item). Fine at this volume; revisit if it grows large.
  Stream<List<InkTransaction>> watchAllTransactions() => _db
      .collection(Collections.inkTransactions)
      .snapshots()
      .map((s) => s.docs.map(InkTransaction.fromFirestore).toList());

  /// Manager "pending costs" queue — receipts awaiting a cost.
  Stream<List<InkTransaction>> watchPendingCosts() => _db
      .collection(Collections.inkTransactions)
      .where('cost_status', isEqualTo: InkCostStatus.pending.value)
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkTransaction.fromFirestore).toList()
          ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
        return list;
      });

  /// Manager review queue — flagged (e.g. negative-balance) movements.
  Stream<List<InkTransaction>> watchFlagged() => _db
      .collection(Collections.inkTransactions)
      .where('flagged_for_review', isEqualTo: true)
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkTransaction.fromFirestore).toList()
          ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
        return list;
      });

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
  }) =>
      _db.collection(Collections.inkOtherMeterLogs).add({
        'label': label,
        'reading': reading,
        'reading_date': Timestamp.fromDate(readingDate),
        if (actorClockNo != null) 'actor_clock_no': actorClockNo,
        if (actorName != null) 'actor_name': actorName,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'recorded_at': FieldValue.serverTimestamp(),
      });

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
  /// the meter screen can compute the next reading's delta.
  Stream<Map<String, double>> watchLatestMeterReadings() => _db
      .collection(Collections.inkTransactions)
      .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
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

  /// The most recent [limit] meter readings per item (newest first) — for the
  /// grid view that shows the previous few days alongside the entry field.
  Stream<Map<String, List<({DateTime at, double reading})>>>
      watchRecentMeterReadings({int limit = 4}) => _db
          .collection(Collections.inkTransactions)
          .where('type', isEqualTo: InkTxnType.consumptionMeter.value)
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
    });
    for (final t in inputTxns) {
      await recordTransaction(t);
    }
    await recordTransaction(outputTxn);
    return runId;
  }

  // ---------------------------------------------------------------------------
  // IBCs (ink received in containers)
  // ---------------------------------------------------------------------------

  Stream<List<InkIbc>> watchIbcs({InkIbcStatus? status}) => _db
      .collection(Collections.inkIbcs)
      .snapshots()
      .map((s) {
        var list = s.docs.map(InkIbc.fromFirestore).toList();
        if (status != null) {
          list = list.where((i) => i.status == status).toList();
        }
        list.sort((a, b) => b.receivedDate.compareTo(a.receivedDate));
        return list;
      });

  /// Receiving ink via IBC: registers each IBC (doc id = number) and records
  /// ONE cost-pending `purchase` per colour for the total kg. Receipts are
  /// idempotent (IBC docs keyed by number; purchase key derived from the
  /// numbers), so an offline replay won't duplicate.
  Future<void> recordIbcReceipt({
    required List<InkIbc> ibcs,
    required String supplierName,
    required DateTime effectiveAt,
    required String actorClockNo,
    required String actorName,
  }) async {
    for (final ibc in ibcs) {
      await _db.collection(Collections.inkIbcs).doc(ibc.ibcNumber).set(
            InkIbc(
              ibcNumber: ibc.ibcNumber,
              itemCode: ibc.itemCode,
              kg: ibc.kg,
              receivedDate: effectiveAt,
              supplierName: supplierName,
            ).toFirestore(),
            SetOptions(merge: true),
          );
    }
    final byItem = <String, double>{};
    final numbersByItem = <String, List<String>>{};
    for (final ibc in ibcs) {
      byItem[ibc.itemCode] = (byItem[ibc.itemCode] ?? 0) + ibc.kg;
      (numbersByItem[ibc.itemCode] ??= []).add(ibc.ibcNumber);
    }
    for (final entry in byItem.entries) {
      final nums = numbersByItem[entry.key]!..sort();
      await recordTransaction(InkTransaction(
        type: InkTxnType.purchase,
        stockItemCode: entry.key,
        quantityDelta: entry.value,
        effectiveAt: effectiveAt,
        costStatus: InkCostStatus.pending,
        supplierName: supplierName,
        notes: '${nums.length} IBC(s): ${nums.join(', ')}',
        actorClockNo: actorClockNo,
        actorName: actorName,
        idempotencyKey: 'ibcrcpt_${entry.key}_${nums.join('_')}',
      ));
    }
  }

  /// Transfers an IBC to a tank: marks it transferred and records the toloul
  /// used to wash it as a `consumption_toloul_wash` (ink stock is unaffected —
  /// the ink was already counted at receipt).
  Future<void> transferIbc({
    required InkIbc ibc,
    required String tolulItemCode,
    required double washLitres,
    required DateTime effectiveAt,
    required String actorClockNo,
    required String actorName,
  }) async {
    await _db.collection(Collections.inkIbcs).doc(ibc.ibcNumber).set({
      'status': InkIbcStatus.transferred.value,
      'transferred_date': Timestamp.fromDate(effectiveAt),
      'wash_toloul_litres': washLitres,
    }, SetOptions(merge: true));
    if (washLitres > 0) {
      await recordTransaction(InkTransaction(
        type: InkTxnType.consumptionTolulWash,
        stockItemCode: tolulItemCode,
        quantityDelta: -washLitres,
        effectiveAt: effectiveAt,
        costStatus: InkCostStatus.na,
        ibcNumber: ibc.ibcNumber,
        actorClockNo: actorClockNo,
        actorName: actorName,
        idempotencyKey: 'ibcwash_${ibc.ibcNumber}',
      ));
    }
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
  Future<void> recordMeterPointReadings({
    required DateTime readingDate,
    required List<
            ({String pointId, double reading, double consumption, bool reset})>
        lines,
    required String actorClockNo,
    required String actorName,
  }) async {
    for (final l in lines) {
      await _db.collection(Collections.inkMeterPointReadings).add({
        'point_id': l.pointId,
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

  /// Latest cumulative reading per meter point (for delta computation).
  Stream<Map<String, double>> watchLatestMeterPointReadings() => _db
      .collection(Collections.inkMeterPointReadings)
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
}
