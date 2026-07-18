import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../constants/collections.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../models/waste_stock_item.dart';
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

  static bool isCopperSellSource(String? source) {
    final s = WasteStockSource.fromString(source);
    return s.isCopperSellStaging;
  }

  Stream<CopperInventory> getInventoryStream() {
    return _firestore
        .doc(inventoryPath)
        .snapshots()
        .map((doc) => CopperInventory.fromFirestore(doc));
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
      await _firestore
          .collection(transCollection)
          .doc(id)
          .update({'comments': comments});
    } catch (e) {
      throw Exception('Failed to update transaction comments: $e');
    }
  }

  Future<void> performAddToSort(
      double amountKg, String comments, String userId) async {
    _guardWrite();
    final amount = roundKg(amountKg);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper operations require online connection');
    }
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv =
          inv.copyWith(sortKg: roundKg(inv.sortKg + amount), lastUpdated: now);
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(
          _firestore.collection(transCollection).doc(id),
          CopperTransaction(
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

  Future<void> performPlateBars(
      double amountKg, String comments, String userId) async {
    _guardWrite();
    final amount = roundKg(amountKg);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper operations require online connection');
    }
    await _firestore.runTransaction((tx) async {
      // Reads first (inventory + rods pool pointer + pool doc).
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final pool = await _readCopperPool(tx, kCopperRodsPoolPointerDocId);
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv = inv.copyWith(
        sellKg: roundKg(inv.sellKg + amount),
        sellRodsKg: roundKg(inv.sellRodsKg + amount),
        lastUpdated: now,
        clearActiveCopperWasteBatchId: true,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(
          _firestore.collection(transCollection).doc(id),
          CopperTransaction(
            id: id,
            type: CopperTransaction.plateBars,
            amountKg: amount,
            fromBucket: 'bars',
            toBucket: 'sell_waste_stock',
            timestamp: now,
            comments: comments.isEmpty
                ? 'Staged to Waste stock (Rods)'
                : comments,
            userId: userId,
          ).toFirestore());
      _addKgToCopperPool(
        tx: tx,
        pool: pool,
        pointerDocId: kCopperRodsPoolPointerDocId,
        subtype: WasteStockTypes.copperRods,
        addKg: amount,
        userId: userId,
        now: now,
      );
    });
  }

  Future<void> performSort(
      double reuseKg, double sellKg, String comments, String userId) async {
    _guardWrite();
    final reuse = roundKg(reuseKg);
    final sell = roundKg(sellKg);
    if (reuse < 0 || sell < 0) throw Exception('Amounts cannot be negative');
    final totalKg = roundKg(reuse + sell);
    if (totalKg <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper operations require online connection');
    }
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final CopperPoolRead? pool = sell > 0
          ? await _readCopperPool(tx, kCopperNuggetsPoolPointerDocId)
          : null;
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
        clearActiveCopperWasteBatchId: true,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(
          _firestore.collection(transCollection).doc(id),
          CopperTransaction(
            id: id,
            type: CopperTransaction.sort,
            amountKg: totalKg,
            fromBucket: 'sort',
            toBucket: sell > 0
                ? 'reuse: ${reuse.toStringAsFixed(1)}kg, sell_waste: ${sell.toStringAsFixed(1)}kg'
                : 'reuse: ${reuse.toStringAsFixed(1)}kg, sell: 0kg',
            timestamp: now,
            comments: comments,
            userId: userId,
          ).toFirestore());
      if (sell > 0 && pool != null) {
        _addKgToCopperPool(
          tx: tx,
          pool: pool,
          pointerDocId: kCopperNuggetsPoolPointerDocId,
          subtype: WasteStockTypes.copperNuggets,
          addKg: sell,
          userId: userId,
          now: now,
        );
      }
    });
  }

  Future<void> performUseReuse(
      double amountKg, String comments, String userId) async {
    _guardWrite();
    final requested = roundKg(amountKg);
    if (requested <= 0) throw Exception('Amount must be greater than 0');
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Copper operations require online connection');
    }
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      if (!hasEnoughKg(inv.reuseKg, requested)) {
        throw Exception(
          'Insufficient reuse kg (have ${roundKg(inv.reuseKg).toStringAsFixed(1)}, '
          'asked ${requested.toStringAsFixed(1)})',
        );
      }
      final taken = takeKg(inv.reuseKg, requested);
      final newInv = inv.copyWith(
        reuseKg: subtractKg(inv.reuseKg, taken),
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(
          _firestore.collection(transCollection).doc(id),
          CopperTransaction(
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

  @Deprecated('Sales are recorded via Waste load completion only')
  Future<void> performRecordSale(
      double amountKg, double rPerKg, String comments, String userId) async {
    throw Exception(
      'Record Sale is disabled on Copper. Complete a Copper Waste collection '
      'to record the commercial sale.',
    );
  }

  static bool isDustKg(double kg) => kg > 0 && roundKg(kg) <= 0.1;

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
      final rodsPool = await _readCopperPool(tx, kCopperRodsPoolPointerDocId);
      final nuggetsPool =
          await _readCopperPool(tx, kCopperNuggetsPoolPointerDocId);
      final inv = CopperInventory.fromFirestore(invDoc);
      final parts = <String>[];
      var sort = inv.sortKg;
      var reuse = inv.reuseKg;
      var sell = inv.sellKg;
      var rods = inv.sellRodsKg;
      var nuggets = inv.sellNuggetsKg;
      var totalCleared = 0.0;
      var rodsCleared = 0.0;
      var nuggetsCleared = 0.0;

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
        rodsCleared = rods;
        nuggetsCleared = nuggets;
        sell = 0;
        rods = 0;
        nuggets = 0;
      } else {
        if (isDustKg(rods)) {
          totalCleared += rods;
          parts.add('rods ${roundKg(rods).toStringAsFixed(1)}');
          rodsCleared = rods;
          rods = 0;
          sell = roundKg(nuggets);
        }
        if (isDustKg(nuggets)) {
          totalCleared += nuggets;
          parts.add('nuggets ${roundKg(nuggets).toStringAsFixed(1)}');
          nuggetsCleared = nuggets;
          nuggets = 0;
          sell = roundKg(rods);
        }
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
      tx.set(
          _firestore.collection(transCollection).doc(id),
          CopperTransaction(
            id: id,
            type: CopperTransaction.zeroDust,
            amountKg: roundKg(totalCleared),
            fromBucket: parts.join(', '),
            toBucket: 'cleared',
            timestamp: now,
            comments: comments.trim(),
            userId: userId,
          ).toFirestore());
      if (rodsCleared > 0) {
        _reduceCopperPoolBy(
          tx: tx,
          pool: rodsPool,
          reduceKg: rodsCleared,
          now: now,
        );
      }
      if (nuggetsCleared > 0) {
        _reduceCopperPoolBy(
          tx: tx,
          pool: nuggetsPool,
          reduceKg: nuggetsCleared,
          now: now,
        );
      }
    });
  }

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
      final rodsPool = b == 'sell'
          ? await _readCopperPool(tx, kCopperRodsPoolPointerDocId)
          : null;
      final nuggetsPool = b == 'sell'
          ? await _readCopperPool(tx, kCopperNuggetsPoolPointerDocId)
          : null;
      final inv = CopperInventory.fromFirestore(invDoc);
      double nextSort = inv.sortKg;
      double nextReuse = inv.reuseKg;
      double nextSell = inv.sellKg;
      double nextRods = inv.sellRodsKg;
      double nextNuggets = inv.sellNuggetsKg;
      double rodsDelta = 0;
      double nuggetsDelta = 0;

      if (b == 'sort') {
        nextSort = roundKg(inv.sortKg + delta);
        if (nextSort < 0) throw Exception('Sort would go negative');
      } else if (b == 'reuse') {
        nextReuse = roundKg(inv.reuseKg + delta);
        if (nextReuse < 0) throw Exception('Reuse would go negative');
      } else {
        nextSell = roundKg(inv.sellKg + delta);
        if (nextSell < 0) throw Exception('Sell would go negative');
        if (delta > 0) {
          nextNuggets = roundKg(nextNuggets + delta);
          nuggetsDelta = delta;
        } else {
          var left = -delta;
          final fromNuggets = takeKg(nextNuggets, left);
          nextNuggets = subtractKg(nextNuggets, fromNuggets);
          nuggetsDelta = -fromNuggets;
          left = roundKg(left - fromNuggets);
          if (left > 0) {
            final fromRods = takeKg(nextRods, left);
            nextRods = subtractKg(nextRods, fromRods);
            rodsDelta = -fromRods;
          }
        }
        nextSell = roundKg(nextRods + nextNuggets);
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
      tx.set(
          _firestore.collection(transCollection).doc(id),
          CopperTransaction(
            id: id,
            type: CopperTransaction.adjust,
            amountKg: delta.abs(),
            fromBucket: b,
            toBucket: delta > 0 ? '+$delta' : '$delta',
            timestamp: now,
            comments: comments.trim(),
            userId: userId,
          ).toFirestore());
      if (b == 'sell' && rodsPool != null && nuggetsPool != null) {
        if (rodsDelta > 0) {
          _addKgToCopperPool(
            tx: tx,
            pool: rodsPool,
            pointerDocId: kCopperRodsPoolPointerDocId,
            subtype: WasteStockTypes.copperRods,
            addKg: rodsDelta,
            userId: userId,
            now: now,
          );
        } else if (rodsDelta < 0) {
          _reduceCopperPoolBy(
            tx: tx,
            pool: rodsPool,
            reduceKg: -rodsDelta,
            now: now,
          );
        }
        if (nuggetsDelta > 0) {
          _addKgToCopperPool(
            tx: tx,
            pool: nuggetsPool,
            pointerDocId: kCopperNuggetsPoolPointerDocId,
            subtype: WasteStockTypes.copperNuggets,
            addKg: nuggetsDelta,
            userId: userId,
            now: now,
          );
        } else if (nuggetsDelta < 0) {
          _reduceCopperPoolBy(
            tx: tx,
            pool: nuggetsPool,
            reduceKg: -nuggetsDelta,
            now: now,
          );
        }
      }
    });
  }

  /// When copper waste stock is marked loaded, reduce inventory sell mirrors.
  Future<void> deductSellForLoadedStockIds(List<String> stockIds) async {
    if (stockIds.isEmpty) return;
    if (!await ConnectivityService().isOnline()) return;

    for (final stockId in stockIds) {
      try {
        await _firestore.runTransaction((tx) async {
          final stockRef =
              _firestore.collection(Collections.wasteStock).doc(stockId);
          final stockSnap = await tx.get(stockRef);
          if (!stockSnap.exists) return;
          final data = stockSnap.data() ?? {};
          if (!isCopperSellSource(data['source'] as String?)) return;
          // Only deduct once when transitioning — weight still on doc.
          final weight =
              ((data['estimated_weight_kg'] as num?)?.toDouble() ?? 0);
          if (weight <= 0) return;
          final subtype = (data['subtype'] as String?) ?? '';
          final invDoc = await tx.get(_firestore.doc(inventoryPath));
          final inv = CopperInventory.fromFirestore(invDoc);
          final now = Timestamp.now();
          var rods = inv.sellRodsKg;
          var nuggets = inv.sellNuggetsKg;
          if (subtype == WasteStockTypes.copperRods) {
            rods = subtractKg(rods, weight);
          } else if (subtype == WasteStockTypes.copperNuggets) {
            nuggets = subtractKg(nuggets, weight);
          } else {
            // Unknown subtype: reduce total sell proportionally via nuggets first.
            final takeN = takeKg(nuggets, weight);
            nuggets = subtractKg(nuggets, takeN);
            final left = roundKg(weight - takeN);
            if (left > 0) rods = subtractKg(rods, left);
          }
          final sell = roundKg(rods + nuggets);
          tx.update(_firestore.doc(inventoryPath), inv.copyWith(
            sellKg: sell,
            sellRodsKg: rods,
            sellNuggetsKg: nuggets,
            lastUpdated: now,
            clearActiveCopperWasteBatchId: true,
          ).toFirestore());
          // Zero weight on loaded stock so re-mark is idempotent.
          tx.update(stockRef, {
            'estimated_weight_kg': 0,
            'updated_at': now,
          });
        });
      } catch (e) {
        // Non-fatal: load path must not fail if inventory already adjusted.
        debugPrint('deductSellForLoadedStockIds $stockId: $e');
      }
    }
  }

  /// Records commercial sale when a Copper Waste load completes.
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
      final existing =
          await tx.get(_firestore.collection(transCollection).doc(docId));
      if (existing.exists) return;

      tx.set(
          _firestore.collection(transCollection).doc(docId),
          CopperTransaction(
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
      tx.update(
          _firestore.doc(inventoryPath),
          inv
              .copyWith(
                currentRPerKg: rPerKg,
                lastUpdated: now,
              )
              .toFirestore());
    });
  }

  /// One-time / ship-time: ensure on-site waste pools mirror inventory sell.
  Future<void> migrateSellBucketsToWasteStockPools({
    required String userId,
  }) async {
    _guardWrite();
    if (!await ConnectivityService().isOnline()) {
      throw Exception('Migration requires online connection');
    }
    final now = Timestamp.now();
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final rodsPool = await _readCopperPool(tx, kCopperRodsPoolPointerDocId);
      final nuggetsPool =
          await _readCopperPool(tx, kCopperNuggetsPoolPointerDocId);
      final inv = CopperInventory.fromFirestore(invDoc);
      final rods = roundKg(inv.sellRodsKg);
      final nuggets = roundKg(inv.sellNuggetsKg);
      if (rods <= 0 && nuggets <= 0) return;

      if (rods > 0) {
        _setCopperPoolAbsolute(
          tx: tx,
          pool: rodsPool,
          pointerDocId: kCopperRodsPoolPointerDocId,
          subtype: WasteStockTypes.copperRods,
          weightKg: rods,
          userId: userId,
          now: now,
        );
      }
      if (nuggets > 0) {
        _setCopperPoolAbsolute(
          tx: tx,
          pool: nuggetsPool,
          pointerDocId: kCopperNuggetsPoolPointerDocId,
          subtype: WasteStockTypes.copperNuggets,
          weightKg: nuggets,
          userId: userId,
          now: now,
        );
      }
      // Keep inventory as-is (mirror). Clear legacy batch flag.
      tx.update(_firestore.doc(inventoryPath), {
        'last_updated': now,
        'active_copper_waste_batch_id': FieldValue.delete(),
      });
      final auditId = 'migrate_copper_sell_stock_${now.millisecondsSinceEpoch}';
      tx.set(
          _firestore.collection(transCollection).doc(auditId),
          CopperTransaction(
            id: auditId,
            type: CopperTransaction.adjust,
            amountKg: roundKg(rods + nuggets),
            fromBucket: 'sell_split_repair',
            toBucket:
                'waste_stock rods: ${rods.toStringAsFixed(1)}kg, nuggets: ${nuggets.toStringAsFixed(1)}kg',
            timestamp: now,
            comments:
                'Ship migration: stage copper To Sell into waste stock pools for Security collection',
            userId: userId,
          ).toFirestore());
    });
  }

  // ── Sell pool helpers (pointer + running on_site waste_stock) ────────────

  Future<CopperPoolRead> _readCopperPool(
    Transaction tx,
    String pointerDocId,
  ) async {
    final pointerRef =
        _firestore.collection(Collections.wasteStockPoolPointers).doc(pointerDocId);
    final pointerSnap = await tx.get(pointerRef);
    final poolId = pointerSnap.data()?['current_pool_stock_id'] as String?;
    DocumentSnapshot<Map<String, dynamic>>? poolSnap;
    if (poolId != null && poolId.isNotEmpty) {
      poolSnap =
          await tx.get(_firestore.collection(Collections.wasteStock).doc(poolId));
    }
    return CopperPoolRead(
      pointerRef: pointerRef,
      poolId: poolId,
      poolSnap: poolSnap,
    );
  }

  bool _poolIsOpen(CopperPoolRead pool) {
    final data = pool.poolSnap?.data();
    if (data == null || pool.poolSnap?.exists != true) return false;
    if (data['is_deleted'] == true) return false;
    final status = (data['status'] as String?) ?? 'on_site';
    return status == WasteStockStatus.onSite.value;
  }

  void _addKgToCopperPool({
    required Transaction tx,
    required CopperPoolRead pool,
    required String pointerDocId,
    required String subtype,
    required double addKg,
    required String userId,
    required Timestamp now,
  }) {
    final amount = roundKg(addKg);
    if (amount <= 0) return;

    if (_poolIsOpen(pool) && pool.poolId != null) {
      final poolRef =
          _firestore.collection(Collections.wasteStock).doc(pool.poolId);
      final current =
          (pool.poolSnap!.data()?['estimated_weight_kg'] as num?)?.toDouble() ??
              0;
      tx.update(poolRef, {
        'estimated_weight_kg': roundKg(current + amount),
        'updated_at': now,
        'source': WasteStockSource.copperSell.value,
      });
      return;
    }

    final newId = _uuid.v4();
    final poolRef = _firestore.collection(Collections.wasteStock).doc(newId);
    tx.set(poolRef, {
      'waste_type': WasteStockTypes.copperWaste,
      'subtype': subtype,
      'photos': <String>[],
      'quantity': 1,
      'estimated_weight_kg': amount,
      'source': WasteStockSource.copperSell.value,
      'source_ref': 'copper_sell_pool:$pointerDocId',
      'visibility': WasteStockVisibility.managerOnly.value,
      'auto_created': true,
      'status': WasteStockStatus.onSite.value,
      'created_by': userId,
      'created_by_name': 'System (copper sell stage)',
      'is_deleted': false,
      'created_at': now,
      'updated_at': now,
      'notes':
          'Staged from Copper module when Pre Press moved metal to To Sell',
    });
    tx.set(pool.pointerRef, {
      'current_pool_stock_id': newId,
      'updated_at': now,
    }, SetOptions(merge: true));
  }

  void _setCopperPoolAbsolute({
    required Transaction tx,
    required CopperPoolRead pool,
    required String pointerDocId,
    required String subtype,
    required double weightKg,
    required String userId,
    required Timestamp now,
  }) {
    final weight = roundKg(weightKg);
    if (weight <= 0) return;

    if (_poolIsOpen(pool) && pool.poolId != null) {
      tx.update(
        _firestore.collection(Collections.wasteStock).doc(pool.poolId),
        {
          'estimated_weight_kg': weight,
          'updated_at': now,
          'source': WasteStockSource.copperSell.value,
        },
      );
      return;
    }
    _addKgToCopperPool(
      tx: tx,
      pool: pool,
      pointerDocId: pointerDocId,
      subtype: subtype,
      addKg: weight,
      userId: userId,
      now: now,
    );
  }

  void _reduceCopperPoolBy({
    required Transaction tx,
    required CopperPoolRead pool,
    required double reduceKg,
    required Timestamp now,
  }) {
    final reduce = roundKg(reduceKg);
    if (reduce <= 0 || !_poolIsOpen(pool) || pool.poolId == null) return;
    final current =
        (pool.poolSnap!.data()?['estimated_weight_kg'] as num?)?.toDouble() ??
            0;
    final next = subtractKg(current, reduce);
    final poolRef =
        _firestore.collection(Collections.wasteStock).doc(pool.poolId);
    if (next <= 0) {
      tx.update(poolRef, {
        'estimated_weight_kg': 0,
        'status': WasteStockStatus.disposed.value,
        'updated_at': now,
      });
    } else {
      tx.update(poolRef, {
        'estimated_weight_kg': next,
        'updated_at': now,
      });
    }
  }

  /// Legacy no-op — continuous pools replaced threshold batches.
  @Deprecated('Threshold batch model removed')
  Future<void> clearActiveBatchIfNoOnSiteThresholdStock() async {
    try {
      await _firestore.doc(inventoryPath).update({
        'active_copper_waste_batch_id': FieldValue.delete(),
        'last_updated': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}

class CopperPoolRead {
  const CopperPoolRead({
    required this.pointerRef,
    required this.poolId,
    required this.poolSnap,
  });

  final DocumentReference<Map<String, dynamic>> pointerRef;
  final String? poolId;
  final DocumentSnapshot<Map<String, dynamic>>? poolSnap;
}
