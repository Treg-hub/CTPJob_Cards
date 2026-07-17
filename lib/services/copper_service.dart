import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../constants/collections.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../models/waste_stock_source.dart';
import '../services/connectivity_service.dart';
import '../utils/persona_audit.dart';

class CopperService {
  void _guardWrite() => assertPersonaSubmitAllowed();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  static const String inventoryPath = 'copper_inventory/main';
  static const String transCollection = 'copper_transactions';

  /// Floor scales to 0.1 kg. Snap display/storage to that precision.
  static double roundKg(double kg) => (kg * 10).roundToDouble() / 10;

  /// Half a display unit — remainder under this is float dust, treat as empty.
  static const double kgDust = 0.05;

  /// Subtract [amount] from [available] without going negative; zero dust leftovers.
  static double subtractKg(double available, double amount) {
    final left = available - amount;
    if (left <= kgDust) return 0.0;
    return roundKg(left);
  }

  /// Whether [available] covers [requested] (float-safe, allows tiny overshoot).
  static bool hasEnoughKg(double available, double requested) =>
      available + kgDust >= requested;

  /// Amount actually taken when depleting a bucket (never more than available).
  static double takeKg(double available, double requested) {
    if (requested >= available - kgDust) return available;
    return requested;
  }

  Stream<CopperInventory> getInventoryStream() {
    return _firestore.doc(inventoryPath).snapshots().map((doc) => CopperInventory.fromFirestore(doc));
  }

  Future<void> initializeInventory() async {
    final docRef = _firestore.doc(inventoryPath);
    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set(CopperInventory(
        sortKg: 0.0,
        reuseKg: 0.0,
        sellKg: 0.0,
        sellRodsKg: 0.0,
        sellNuggetsKg: 0.0,
        currentRPerKg: 0.0,
        lastUpdated: Timestamp.now(),
      ).toFirestore());
    }
  }

  /// Transactions in [range] (default: last 90 days). Hard limit for reads.
  Stream<List<CopperTransaction>> getTransactionsStream({
    DateTimeRange? range,
    int limit = 300,
  }) {
    final effective = range ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 90)),
          end: DateTime.now().add(const Duration(days: 1)),
        );
    Query query = _firestore
        .collection(transCollection)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(effective.start))
        .where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(effective.end))
        .orderBy('timestamp', descending: true)
        .limit(limit);
    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => CopperTransaction.fromFirestore(doc)).toList());
  }

  Future<void> updateTransactionComments(String id, String comments) async {
    _guardWrite();
    try {
      await _firestore.collection(transCollection).doc(id).update({'comments': comments});
    } catch (e) {
      throw Exception('Failed to update transaction comments: $e');
    }
  }

  Future<void> performAddToSort(double amountKg, String comments, String userId) async {
    _guardWrite();
    final amount = roundKg(amountKg);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv = inv.copyWith(sortKg: roundKg(inv.sortKg + amount), lastUpdated: now);
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.addToSort,
        amountKg: amount,
        fromBucket: 'baths',
        toBucket: 'sort',
        timestamp: now,
        comments: comments,
        userId: userId,
      ).toFirestore());
    });
  }

  Future<void> performPlateBars(double amountKg, String comments, String userId) async {
    _guardWrite();
    final amount = roundKg(amountKg);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv = inv.copyWith(
        sellKg: roundKg(inv.sellKg + amount),
        sellRodsKg: roundKg(inv.sellRodsKg + amount),
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.plateBars,
        amountKg: amount,
        fromBucket: 'bars',
        toBucket: 'sell',
        timestamp: now,
        comments: comments,
        userId: userId,
      ).toFirestore());
      await _maybeCreateCopperWasteStock(tx, newInv, userId, now);
    });
  }

  Future<void> performSort(double reuseKg, double sellKg, String comments, String userId) async {
    _guardWrite();
    final reuse = roundKg(reuseKg);
    final sell = roundKg(sellKg);
    if (reuse < 0 || sell < 0) throw Exception('Amounts cannot be negative');
    final totalKg = roundKg(reuse + sell);
    if (totalKg <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      if (!hasEnoughKg(inv.sortKg, totalKg)) {
        throw Exception(
          'Insufficient sort kg (have ${roundKg(inv.sortKg).toStringAsFixed(1)}, '
          'need ${totalKg.toStringAsFixed(1)})',
        );
      }
      final newInv = inv.copyWith(
        sortKg: subtractKg(inv.sortKg, totalKg),
        reuseKg: roundKg(inv.reuseKg + reuse),
        sellKg: roundKg(inv.sellKg + sell),
        sellNuggetsKg: roundKg(inv.sellNuggetsKg + sell),
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.sort,
        amountKg: totalKg,
        fromBucket: 'sort',
        toBucket:
            'reuse: ${reuse.toStringAsFixed(1)}kg, sell: ${sell.toStringAsFixed(1)}kg',
        timestamp: now,
        comments: comments,
        userId: userId,
      ).toFirestore());
      await _maybeCreateCopperWasteStock(tx, newInv, userId, now);
    });
  }

  Future<void> performUseReuse(double amountKg, String comments, String userId) async {
    _guardWrite();
    final requested = roundKg(amountKg);
    if (requested <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      if (!hasEnoughKg(inv.reuseKg, requested)) {
        throw Exception(
          'Insufficient reuse kg (have ${roundKg(inv.reuseKg).toStringAsFixed(1)}, '
          'asked ${requested.toStringAsFixed(1)})',
        );
      }
      // Clear the bucket when the operator takes "all" of a displayed remainder
      // (e.g. UI shows 0.1 kg but float store is 0.0999…).
      final taken = takeKg(inv.reuseKg, requested);
      final newInv = inv.copyWith(
        reuseKg: subtractKg(inv.reuseKg, taken),
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.useReuse,
        amountKg: roundKg(taken),
        fromBucket: 'reuse',
        toBucket: 'used',
        timestamp: now,
        comments: comments,
        userId: userId,
      ).toFirestore());
    });
  }

  /// Removed from product path — all commercial sales go through Waste load
  /// completion (`recordSaleFromWasteLoad`). Kept only so old call sites fail loudly.
  @Deprecated('Sales are recorded via Waste load completion only')
  Future<void> performRecordSale(double amountKg, double rPerKg, String comments, String userId) async {
    throw Exception(
      'Record Sale is disabled on Copper. Complete a Copper Waste collection '
      'to record the commercial sale.',
    );
  }

  /// True when a bucket has a displayable leftover ≤ 0.1 kg (float dust).
  static bool isDustKg(double kg) => kg > 0 && roundKg(kg) <= 0.1;

  /// Admin: zero sort/reuse/sell (and rod/nugget subs when sell clears) when dust.
  Future<void> performZeroDust({
    required String userId,
    required String comments,
  }) async {
    _guardWrite();
    if (comments.trim().isEmpty) {
      throw Exception('Comment required when zeroing dust');
    }
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper operations require online connection');
    }
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final parts = <String>[];
      var sort = inv.sortKg;
      var reuse = inv.reuseKg;
      var sell = inv.sellKg;
      var rods = inv.sellRodsKg;
      var nuggets = inv.sellNuggetsKg;
      var totalCleared = 0.0;

      if (isDustKg(sort)) {
        totalCleared += sort;
        parts.add('sort ${roundKg(sort).toStringAsFixed(1)}');
        sort = 0;
      }
      if (isDustKg(reuse)) {
        totalCleared += reuse;
        parts.add('reuse ${roundKg(reuse).toStringAsFixed(1)}');
        reuse = 0;
      }
      if (isDustKg(sell)) {
        totalCleared += sell;
        parts.add('sell ${roundKg(sell).toStringAsFixed(1)}');
        sell = 0;
        rods = 0;
        nuggets = 0;
      } else {
        if (isDustKg(rods)) {
          totalCleared += rods;
          parts.add('rods ${roundKg(rods).toStringAsFixed(1)}');
          rods = 0;
        }
        if (isDustKg(nuggets)) {
          totalCleared += nuggets;
          parts.add('nuggets ${roundKg(nuggets).toStringAsFixed(1)}');
          nuggets = 0;
        }
        sell = roundKg(rods + nuggets);
      }

      if (parts.isEmpty) {
        throw Exception('No dust ≤ 0.1 kg to clear');
      }

      final newInv = inv.copyWith(
        sortKg: sort,
        reuseKg: reuse,
        sellKg: sell,
        sellRodsKg: rods,
        sellNuggetsKg: nuggets,
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.zeroDust,
        amountKg: roundKg(totalCleared),
        fromBucket: parts.join(', '),
        toBucket: 'cleared',
        timestamp: now,
        comments: comments.trim(),
        userId: userId,
      ).toFirestore());
    });
  }

  /// Admin: apply a signed delta to one bucket (sort | reuse | sell).
  Future<void> performAdjust({
    required String bucket,
    required double deltaKg,
    required String comments,
    required String userId,
  }) async {
    _guardWrite();
    final delta = roundKg(deltaKg);
    if (delta == 0) throw Exception('Delta must not be 0');
    if (comments.trim().isEmpty) {
      throw Exception('Comment required for adjust');
    }
    final b = bucket.trim().toLowerCase();
    if (b != 'sort' && b != 'reuse' && b != 'sell') {
      throw Exception('Bucket must be sort, reuse, or sell');
    }
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper operations require online connection');
    }
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      double nextSort = inv.sortKg;
      double nextReuse = inv.reuseKg;
      double nextSell = inv.sellKg;
      double nextRods = inv.sellRodsKg;
      double nextNuggets = inv.sellNuggetsKg;

      if (b == 'sort') {
        nextSort = roundKg(inv.sortKg + delta);
        if (nextSort < 0) throw Exception('Sort would go negative');
      } else if (b == 'reuse') {
        nextReuse = roundKg(inv.reuseKg + delta);
        if (nextReuse < 0) throw Exception('Reuse would go negative');
      } else {
        nextSell = roundKg(inv.sellKg + delta);
        if (nextSell < 0) throw Exception('Sell would go negative');
        // Keep subtype total aligned with sell when adjusting sell alone.
        final sub = roundKg(nextRods + nextNuggets);
        if (sub <= 0 || nextSell == 0) {
          nextRods = 0;
          nextNuggets = nextSell;
        } else {
          // Prefer putting positive delta on nuggets; negative reduce nuggets then rods.
          if (delta > 0) {
            nextNuggets = roundKg(nextNuggets + delta);
          } else {
            var left = -delta;
            final fromNuggets = takeKg(nextNuggets, left);
            nextNuggets = subtractKg(nextNuggets, fromNuggets);
            left = roundKg(left - fromNuggets);
            if (left > 0) {
              nextRods = subtractKg(nextRods, left);
            }
          }
          nextSell = roundKg(nextRods + nextNuggets);
        }
      }

      final newInv = inv.copyWith(
        sortKg: nextSort,
        reuseKg: nextReuse,
        sellKg: nextSell,
        sellRodsKg: nextRods,
        sellNuggetsKg: nextNuggets,
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.adjust,
        amountKg: delta.abs(),
        fromBucket: b,
        toBucket: delta > 0 ? '+$delta' : '$delta',
        timestamp: now,
        comments: comments.trim(),
        userId: userId,
      ).toFirestore());
    });
  }

  /// Records commercial sale when a Copper Waste load completes. Does not touch sell buckets.
  Future<void> recordSaleFromWasteLoad({
    required String loadId,
    required String? loadNumber,
    required String subtype,
    required double amountKg,
    required double rPerKg,
    required String userId,
    String comments = '',
  }) async {
    _guardWrite();
    if (amountKg <= 0 || rPerKg <= 0) return;
    final docId = 'waste_sale_${loadId}_${subtype.toLowerCase()}';
    final now = Timestamp.now();
    final totalValueR = amountKg * rPerKg;
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper sale recording requires online connection');
    }

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(_firestore.collection(transCollection).doc(docId));
      if (existing.exists) return;

      tx.set(_firestore.collection(transCollection).doc(docId), CopperTransaction(
        id: docId,
        type: CopperTransaction.recordSaleFromWaste,
        amountKg: amountKg,
        fromBucket: 'waste_load',
        toBucket: 'sold',
        timestamp: now,
        comments: comments.isNotEmpty
            ? comments
            : 'Recorded from waste load ${loadNumber ?? loadId}',
        rPerKg: rPerKg,
        totalValueR: totalValueR,
        userId: userId,
        wasteLoadId: loadId,
        wasteLoadNumber: loadNumber,
        copperSubtype: subtype,
      ).toFirestore());

      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      tx.update(_firestore.doc(inventoryPath), inv.copyWith(
        currentRPerKg: rPerKg,
        lastUpdated: now,
      ).toFirestore());
    });
  }

  Future<void> _maybeCreateCopperWasteStock(
    Transaction tx,
    CopperInventory inv,
    String userId,
    Timestamp now,
  ) async {
    if (inv.sellKg < kCopperWasteStockThresholdKg) return;
    if (inv.activeCopperWasteBatchId != null &&
        inv.activeCopperWasteBatchId!.isNotEmpty) {
      return;
    }

    final batchId = _uuid.v4();
    final stockIds = <String>[];

    if (inv.sellRodsKg > 0) {
      final stockId = 'copper_stock_rods_$batchId';
      stockIds.add(stockId);
      tx.set(_firestore.collection(Collections.wasteStock).doc(stockId), {
        'waste_type': WasteStockTypes.copperWaste,
        'subtype': WasteStockTypes.copperRods,
        'photos': <String>[],
        'quantity': 1,
        'estimated_weight_kg': inv.sellRodsKg,
        'source': WasteStockSource.copperThreshold.value,
        'source_ref': 'copper_batch:$batchId',
        'visibility': WasteStockVisibility.managerOnly.value,
        'auto_created': true,
        'status': 'on_site',
        'created_by': userId,
        'created_by_name': 'System (copper threshold)',
        'is_deleted': false,
        'created_at': now,
        'updated_at': now,
        'notes': 'Auto-created when copper sell bucket reached ${kCopperWasteStockThresholdKg.toStringAsFixed(0)} kg',
      });
    }

    if (inv.sellNuggetsKg > 0) {
      final stockId = 'copper_stock_nuggets_$batchId';
      stockIds.add(stockId);
      tx.set(_firestore.collection(Collections.wasteStock).doc(stockId), {
        'waste_type': WasteStockTypes.copperWaste,
        'subtype': WasteStockTypes.copperNuggets,
        'photos': <String>[],
        'quantity': 1,
        'estimated_weight_kg': inv.sellNuggetsKg,
        'source': WasteStockSource.copperThreshold.value,
        'source_ref': 'copper_batch:$batchId',
        'visibility': WasteStockVisibility.managerOnly.value,
        'auto_created': true,
        'status': 'on_site',
        'created_by': userId,
        'created_by_name': 'System (copper threshold)',
        'is_deleted': false,
        'created_at': now,
        'updated_at': now,
        'notes': 'Auto-created when copper sell bucket reached ${kCopperWasteStockThresholdKg.toStringAsFixed(0)} kg',
      });
    }

    if (stockIds.isEmpty) return;

    tx.update(_firestore.doc(inventoryPath), inv.copyWith(
      sellKg: 0,
      sellRodsKg: 0,
      sellNuggetsKg: 0,
      activeCopperWasteBatchId: batchId,
      lastUpdated: now,
    ).toFirestore());

    final auditId = 'copper_prepare_$batchId';
    tx.set(_firestore.collection(transCollection).doc(auditId), CopperTransaction(
      id: auditId,
      type: CopperTransaction.prepareForCollection,
      amountKg: inv.sellKg,
      fromBucket: 'sell',
      toBucket: 'waste_stock:${stockIds.join(',')}',
      timestamp: now,
      comments: 'Auto-created waste stock at ${kCopperWasteStockThresholdKg.toStringAsFixed(0)} kg threshold',
      userId: userId,
    ).toFirestore());
  }

  /// Clears [activeCopperWasteBatchId] when all threshold stock has left on_site.
  Future<void> clearActiveBatchIfNoOnSiteThresholdStock() async {
    final invSnap = await _firestore.doc(inventoryPath).get();
    final inv = CopperInventory.fromFirestore(invSnap);
    if (inv.activeCopperWasteBatchId == null) return;

    final stockSnap = await _firestore
        .collection(Collections.wasteStock)
        .where('source', isEqualTo: WasteStockSource.copperThreshold.value)
        .where('status', isEqualTo: 'on_site')
        .limit(1)
        .get();

    final hasOnSite = stockSnap.docs.any((d) => d.data()['is_deleted'] != true);
    if (hasOnSite) return;

    await _firestore.doc(inventoryPath).update({
      'active_copper_waste_batch_id': FieldValue.delete(),
      'last_updated': FieldValue.serverTimestamp(),
    });
  }
}