import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the guidance tips on the Create Job Card screen are shown.
/// Per-device preference (same pattern as [fleetTipsVisibleProvider]) — once
/// employees know the ropes they can hide the tips to free up space, and turn
/// them back on from Settings → Preferences.
final jobCardTipsVisibleProvider = NotifierProvider<JobCardTipsNotifier, bool>(
  JobCardTipsNotifier.new,
);

class JobCardTipsNotifier extends Notifier<bool> {
  static const _prefsKey = 'jobCardTipsVisible';

  @override
  bool build() {
    _load();
    return true; // shown by default until the stored preference loads
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefsKey) ?? true;
  }

  Future<void> setVisible(bool visible) async {
    state = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, visible);
  }
}
