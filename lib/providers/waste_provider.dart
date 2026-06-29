import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_settings.dart';
import '../services/waste_service.dart';

/// Singleton WasteService — all waste screens share one instance so the
/// in-memory session queues (_sessionOfflinePhotoQueue, etc.) are consistent.
final wasteServiceProvider = Provider<WasteService>((ref) => WasteService());

final wasteSettingsProvider = StreamProvider<WasteSettings>((ref) {
  return ref.watch(wasteServiceProvider).watchSettings();
});

// ---------------------------------------------------------------------------
// STOCK ITEM SELECTION — ephemeral state used in WasteScheduleLoadScreen
// ---------------------------------------------------------------------------

class StockSelectionState {
  final Set<String> selectedIds;
  const StockSelectionState({this.selectedIds = const {}});

  StockSelectionState copyWith({Set<String>? selectedIds}) =>
      StockSelectionState(selectedIds: selectedIds ?? this.selectedIds);

  bool isSelected(String id) => selectedIds.contains(id);

  StockSelectionState toggle(String id) {
    final next = Set<String>.from(selectedIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    return copyWith(selectedIds: next);
  }
}

class StockSelectionNotifier extends StateNotifier<StockSelectionState> {
  StockSelectionNotifier() : super(const StockSelectionState());

  void toggle(String stockId) => state = state.toggle(stockId);
  void clear() => state = const StockSelectionState();
  void selectAll(List<String> ids) =>
      state = StockSelectionState(selectedIds: Set.from(ids));
}

/// autoDispose so selection is cleared when WasteScheduleLoadScreen is popped.
final stockSelectionProvider =
    StateNotifierProvider.autoDispose<StockSelectionNotifier, StockSelectionState>(
  (ref) => StockSelectionNotifier(),
);

/// Simple state for the in-progress Waste Load being created/edited.
/// This will grow as we add more screens (items, photos, signature, etc.).
class CurrentWasteLoadState {
  final WasteLoad? load;
  final List<WasteItem> items;
  final bool isLoading;

  const CurrentWasteLoadState({
    this.load,
    this.items = const [],
    this.isLoading = false,
  });

  CurrentWasteLoadState copyWith({
    WasteLoad? load,
    List<WasteItem>? items,
    bool? isLoading,
  }) {
    return CurrentWasteLoadState(
      load: load ?? this.load,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  double get totalWeight => items.fold(0.0, (sum, i) => sum + i.weightKg);
}

final currentWasteLoadProvider = StateNotifierProvider<CurrentWasteLoadNotifier, CurrentWasteLoadState>(
  (ref) => CurrentWasteLoadNotifier(),
);

class CurrentWasteLoadNotifier extends StateNotifier<CurrentWasteLoadState> {
  CurrentWasteLoadNotifier() : super(const CurrentWasteLoadState());

  void startNewLoad(WasteLoad initialLoad) {
    state = CurrentWasteLoadState(load: initialLoad, items: []);
  }

  void addItem(WasteItem item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  void removeItem(int index) {
    final newItems = [...state.items]..removeAt(index);
    state = state.copyWith(items: newItems);
  }

  void clear() {
    state = const CurrentWasteLoadState();
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }
}
