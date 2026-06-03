import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/waste_item.dart';
import '../models/waste_load.dart';

// ---------------------------------------------------------------------------
// PALLET SELECTION — ephemeral state used in WasteScheduleLoadScreen
// ---------------------------------------------------------------------------

class PalletSelectionState {
  final Set<String> selectedIds;
  const PalletSelectionState({this.selectedIds = const {}});

  PalletSelectionState copyWith({Set<String>? selectedIds}) =>
      PalletSelectionState(selectedIds: selectedIds ?? this.selectedIds);

  bool isSelected(String id) => selectedIds.contains(id);

  PalletSelectionState toggle(String id) {
    final next = Set<String>.from(selectedIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    return copyWith(selectedIds: next);
  }
}

class PalletSelectionNotifier extends StateNotifier<PalletSelectionState> {
  PalletSelectionNotifier() : super(const PalletSelectionState());

  void toggle(String palletId) => state = state.toggle(palletId);
  void clear() => state = const PalletSelectionState();
  void selectAll(List<String> ids) =>
      state = PalletSelectionState(selectedIds: Set.from(ids));
}

/// autoDispose so selection is cleared when WasteScheduleLoadScreen is popped.
final palletSelectionProvider =
    StateNotifierProvider.autoDispose<PalletSelectionNotifier, PalletSelectionState>(
  (ref) => PalletSelectionNotifier(),
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
