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

  /// Do not flip inventory to loading/error on write — the screen owns the
  /// submit spinner, and a failed write must keep the last known buckets visible.
  Future<void> performAddToSort(double kg, String comments, String clockNo) async {
    await _service.performAddToSort(kg, comments, clockNo);
  }

  Future<void> performPlateBars(double kg, String comments, String clockNo) async {
    await _service.performPlateBars(kg, comments, clockNo);
  }

  Future<void> performUseReuse(double kg, String comments, String clockNo) async {
    await _service.performUseReuse(kg, comments, clockNo);
  }

  Future<void> performSort(double kgToReuse, double kgToSell, String comments, String clockNo) async {
    await _service.performSort(kgToReuse, kgToSell, comments, clockNo);
  }

  Future<void> performZeroDust({
    required String comments,
    required String clockNo,
  }) async {
    await _service.performZeroDust(userId: clockNo, comments: comments);
  }

  Future<void> performAdjust({
    required String bucket,
    required double deltaKg,
    required String comments,
    required String clockNo,
  }) async {
    await _service.performAdjust(
      bucket: bucket,
      deltaKg: deltaKg,
      comments: comments,
      userId: clockNo,
    );
  }
}
