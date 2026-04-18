import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/copper_inventory.dart';
import '../services/copper_service.dart';

final copperNotifierProvider = StateNotifierProvider<CopperNotifier, AsyncValue<CopperInventory>>((ref) {
  return CopperNotifier();
});

class CopperNotifier extends StateNotifier<AsyncValue<CopperInventory>> {
  CopperNotifier() : super(const AsyncValue.loading()) {
    _loadInventory();
  }

  final CopperService _service = CopperService();
  Stream<CopperInventory>? _inventoryStream;

  Stream<CopperInventory> get inventoryStream {
    _inventoryStream ??= _service.getInventoryStream();
    return _inventoryStream!;
  }

  void _loadInventory() async {
    try {
      await _service.initializeInventory();
      inventoryStream.listen((inventory) {
        state = AsyncValue.data(inventory);
      }, onError: (error) {
        state = AsyncValue.error(error, StackTrace.current);
      });
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> performAddToSort(double kg, String comments, String clockNo) async {
    state = const AsyncValue.loading();
    try {
      await _service.performAddToSort(kg, comments, clockNo);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> performPlateBars(double kg, String comments, String clockNo) async {
    state = const AsyncValue.loading();
    try {
      await _service.performPlateBars(kg, comments, clockNo);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> performUseReuse(double kg, String comments, String clockNo) async {
    state = const AsyncValue.loading();
    try {
      await _service.performUseReuse(kg, comments, clockNo);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> performRecordSale(double kg, double rPerKg, String comments, String clockNo) async {
    state = const AsyncValue.loading();
    try {
      await _service.performRecordSale(kg, rPerKg, comments, clockNo);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> performSort(double kgToReuse, double kgToSell, String comments, String clockNo) async {
    state = const AsyncValue.loading();
    try {
      await _service.performSort(kgToReuse, kgToSell, comments, clockNo);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}