import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the mechanic guidance banners (FleetMechanicGuideBanner) are
/// shown. Per-device preference, same persistence pattern as
/// [ThemeNotifier] — mechanics can dismiss the tips once they know the
/// ropes, and turn them back on later from Settings.
final fleetTipsVisibleProvider = NotifierProvider<FleetTipsNotifier, bool>(
  FleetTipsNotifier.new,
);

class FleetTipsNotifier extends Notifier<bool> {
  static const _prefsKey = 'fleetMechanicTipsVisible';

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
