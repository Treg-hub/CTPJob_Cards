import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../services/connectivity_service.dart';

class CopperService {
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
        currentRPerKg: 0.0,
        lastUpdated: Timestamp.now(),
      ).toFirestore());
    }
  }

  Stream<List<CopperTransaction>> getTransactionsStream({DateTimeRange? range}) {
    Query query = _firestore.collection(transCollection).orderBy('timestamp', descending: true);
    if (range != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
                  .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(range.end));
    }
    return query.snapshots().map((snapshot) => snapshot.docs.map((doc) => CopperTransaction.fromFirestore(doc)).toList());
  }

  Future<void> updateTransactionComments(String id, String comments) async {
    try {
      await _firestore.collection(transCollection).doc(id).update({'comments': comments});
    } catch (e) {
      throw Exception('Failed to update transaction comments: $e');
    }
  }

  Future<void> performAddToSort(double amountKg, String comments, String userId) async {
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
    final id = _uuid.v4();
    final now = Timestamp.now();
    if (!await ConnectivityService().isOnline()) throw Exception('Copper operations require online connection');
    await _firestore.runTransaction((tx) async {
      final invDoc = await tx.get(_firestore.doc(inventoryPath));
      final inv = CopperInventory.fromFirestore(invDoc);
      final newInv = inv.copyWith(sellKg: inv.sellKg + amountKg, lastUpdated: now);
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
    });
  }

  Future<void> performSort(double reuseKg, double sellKg, String comments, String userId) async {
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
        lastUpdated: now,
      );
      tx.update(_firestore.doc(inventoryPath), newInv.toFirestore());
      tx.set(_firestore.collection(transCollection).doc(id), CopperTransaction(
        id: id,
        type: CopperTransaction.sort,
        amountKg: totalKg,
        fromBucket: 'sort',
        toBucket: 'reuse+sell',
        timestamp: now,
        comments: comments,
        userId: userId,
      ).toFirestore());
    });
  }

  Future<void> performUseReuse(double amountKg, String comments, String userId) async {
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
}
