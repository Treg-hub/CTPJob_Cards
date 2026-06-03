import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_work_part.dart';
import '../services/fleet_service.dart';

final _fleetService = FleetService();

// ---------------------------------------------------------------------------
// Settings (loaded once per session, used for role derivation in home_screen)
// ---------------------------------------------------------------------------

final fleetSettingsProvider = FutureProvider<FleetSettings>((ref) async {
  return _fleetService.getSettings();
});

// ---------------------------------------------------------------------------
// Asset picker selection — persists the chosen asset during issue reporting
// and work logging flows so the user doesn't re-pick on each screen.
// ---------------------------------------------------------------------------

final selectedFleetAssetProvider = StateProvider<FleetAsset?>((ref) => null);

// ---------------------------------------------------------------------------
// In-progress work parts — mirrors the waste items pattern.
// Holds parts being entered during the Log Work form before the record is saved.
// ---------------------------------------------------------------------------

class _WorkPartsNotifier extends StateNotifier<List<FleetWorkPart>> {
  _WorkPartsNotifier() : super([]);

  void addPart(FleetWorkPart part) => state = [...state, part];

  void removePart(int index) {
    final updated = [...state];
    updated.removeAt(index);
    state = updated;
  }

  void updatePart(int index, FleetWorkPart updated) {
    final list = [...state];
    list[index] = updated;
    state = list;
  }

  void clear() => state = [];
}

final currentWorkPartsProvider =
    StateNotifierProvider<_WorkPartsNotifier, List<FleetWorkPart>>(
  (ref) => _WorkPartsNotifier(),
);

// ---------------------------------------------------------------------------
// Linked issue IDs selected during the Log Work form
// ---------------------------------------------------------------------------

final linkedIssueIdsProvider = StateProvider<List<String>>((ref) => []);
