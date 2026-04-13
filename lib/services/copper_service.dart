import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/copper_transaction.dart';

class CopperService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<CopperTransaction>> getTransactionsStream() {
    return _firestore
        .collection('copperTransactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => CopperTransaction.fromFirestore(doc)).toList());
  }

  Future<void> addTransaction(CopperTransaction transaction) async {
    try {
      await _firestore.collection('copperTransactions').add(transaction.toFirestore());
    } catch (e) {
      throw Exception('Failed to add copper transaction: $e');
    }
  }

  Stream<Map<CopperType, double>> getTotalsStream() {
    return getTransactionsStream().map((transactions) {
      final totals = <CopperType, double>{};
      for (final tx in transactions) {
        totals[tx.type] = (totals[tx.type] ?? 0.0) + tx.kg;
      }
      return totals;
    });
  }

  Future<double> getTotalForType(CopperType type) async {
    final snapshot = await _firestore
        .collection('copperTransactions')
        .where('type', isEqualTo: type.name)
        .get();
    double total = 0.0;
    for (final doc in snapshot.docs) {
      total += (doc.data()['kg'] as num?)?.toDouble() ?? 0.0;
    }
    return total;
  }
}