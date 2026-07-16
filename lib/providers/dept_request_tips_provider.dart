import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Dept Request guidance tips are shown (list + create).
/// Restore from Settings → Preferences after hide.
final deptRequestTipsVisibleProvider =
    NotifierProvider<DeptRequestTipsNotifier, bool>(DeptRequestTipsNotifier.new);

class DeptRequestTipsNotifier extends Notifier<bool> {
  static const _prefsKey = 'deptRequestTipsVisible';

  @override
  bool build() {
    _load();
    return true;
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
