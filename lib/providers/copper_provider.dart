import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../services/copper_service.dart';

final copperNotifierProvider = NotifierProvider<CopperNotifier, void>(CopperNotifier.new);

class CopperNotifier extends Notifier<void> {
  final CopperService _copperService = CopperService();

  @override
  void build() {}

  Stream<CopperInventory> get inventoryStream => _copperService.getInventoryStream();

  Stream<List<CopperTransaction>> getTransactionsStream({DateTimeRange? range}) =>
      _copperService.getTransactionsStream(range: range);

  Future<void> updateTransactionComments(String id, String comments) async {
    await _copperService.updateTransactionComments(id, comments);
  }

  Future<void> performAddToSort(double amountKg, String comments, String userId) async {
    await _copperService.performAddToSort(amountKg, comments, userId);
  }

  Future<void> performPlateBars(double amountKg, String comments, String userId) async {
    await _copperService.performPlateBars(amountKg, comments, userId);
  }

  Future<void> performSort(double reuseKg, double sellKg, String comments, String userId) async {
    await _copperService.performSort(reuseKg, sellKg, comments, userId);
  }

  Future<void> performUseReuse(double amountKg, String comments, String userId) async {
    await _copperService.performUseReuse(amountKg, comments, userId);
  }

  Future<void> performRecordSale(double amountKg, double rPerKg, String comments, String userId) async {
    await _copperService.performRecordSale(amountKg, rPerKg, comments, userId);
  }
}