import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Ink Factory guidance banners are shown on capture screens.
/// Per-device preference (same pattern as fleet / job-card tips).
final inkTipsVisibleProvider = NotifierProvider<InkTipsNotifier, bool>(
  InkTipsNotifier.new,
);

class InkTipsNotifier extends Notifier<bool> {
  static const prefsKey = 'inkFactoryTipsVisible';

  @override
  bool build() {
    _load();
    return true;
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(prefsKey) ?? true;
  }

  Future<void> setVisible(bool visible) async {
    state = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, visible);
  }
}
