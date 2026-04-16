import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../services/copper_service.dart';

class CopperProvider with ChangeNotifier {
  final CopperService _copperService = CopperService();

  Stream<CopperInventory> get inventoryStream => _copperService.getInventoryStream();
  Stream<List<CopperTransaction>> getTransactionsStream({DateTimeRange? range}) => _copperService.getTransactionsStream(range: range);

  Future<void> updateTransactionComments(String id, String comments) async {
    await _copperService.updateTransactionComments(id, comments);
    notifyListeners();
  }

  Future<void> performAddToSort(double amountKg, String comments, String userId) async {
    await _copperService.performAddToSort(amountKg, comments, userId);
    notifyListeners();
  }

  Future<void> performPlateBars(double amountKg, String comments, String userId) async {
    await _copperService.performPlateBars(amountKg, comments, userId);
    notifyListeners();
  }

  Future<void> performSort(double reuseKg, double sellKg, String comments, String userId) async {
    await _copperService.performSort(reuseKg, sellKg, comments, userId);
    notifyListeners();
  }

  Future<void> performUseReuse(double amountKg, String comments, String userId) async {
    await _copperService.performUseReuse(amountKg, comments, userId);
    notifyListeners();
  }

  Future<void> performRecordSale(double amountKg, double rPerKg, String comments, String userId) async {
    await _copperService.performRecordSale(amountKg, rPerKg, comments, userId);
    notifyListeners();
  }
}