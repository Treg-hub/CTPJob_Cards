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
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv = inv.copyWith(sortKg: inv.sortKg + amountKg, lastUpdated: now);
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.addToSort,
        amountKg: amountKg,
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
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv = inv.copyWith(
        sellKg: inv.sellKg + amountKg,
        sellRodsKg: inv.sellRodsKg + amountKg,
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.plateBars,
        amountKg: amountKg,
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
    final id = _uuid.v4();
    final now = Timestamp.now();
    final totalKg = reuseKg + sellKg;
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      if (inv.sortKg < totalKg) throw Exception('Insufficient sort kg');
      final newInv = inv.copyWith(
        sortKg: inv.sortKg - totalKg,
        reuseKg: inv.reuseKg + reuseKg,
        sellKg: inv.sellKg + sellKg,
        sellNuggetsKg: inv.sellNuggetsKg + sellKg,
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
       tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
         id: id,
         type: CopperTransaction.sort,
         amountKg: totalKg,
         fromBucket: 'sort',
         toBucket: 'reuse: ${reuseKg.toStringAsFixed(1)}kg, sell: ${sellKg.toStringAsFixed(1)}kg',
         timestamp: now,
         comments: comments,
         userId: userId,
       ).toFirestore());
      await _maybeCreateCopperWasteStock(tx, newInv, userId, now);
    });
  }

  Future<void> performUseReuse(double amountKg, String comments, String userId) async {
    _guardWrite();
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      if (inv.reuseKg < amountKg) throw Exception('Insufficient reuse kg');
      final newInv = inv.copyWith(reuseKg: inv.reuseKg - amountKg, lastUpdated: now);
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.useReuse,
        amountKg: amountKg,
        fromBucket: 'reuse',
        timestamp: now,
        comments: comments,
        userId: userId,
      ).toFirestore());
    });
  }

  Future<void> performRecordSale(double amountKg, double rPerKg, String comments, String userId) async {
    _guardWrite();
    final id = _uuid.v4();
    final now = Timestamp.now();
    final totalValueR = amountKg * rPerKg;
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      if (inv.sellKg < amountKg) throw Exception('Insufficient sell kg');
      final newInv = inv.copyWith(sellKg: inv.sellKg - amountKg, currentRPerKg: rPerKg, lastUpdated: now);
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.recordSale,
        amountKg: amountKg,
        fromBucket: 'sell',
        timestamp: now,
        comments: comments,
        rPerKg: rPerKg,
        totalValueR: totalValueR,
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