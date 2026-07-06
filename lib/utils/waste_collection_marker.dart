import 'package:shared_preferences/shared_preferences.dart';

/// Local idempotency marker for guard collection / finish-loading submits.
/// Cleared when the Hive queue for that load drains or sync lands the status.
abstract final class WasteCollectionMarker {
  static const String prefsPrefix = 'wasteCollectionSubmitted_';

  static String _key(String loadId) => '$prefsPrefix$loadId';

  static Future<bool> hasMarker(String loadId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(loadId));
  }

  static Future<void> setMarker(String loadId, String submitRef) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(loadId), submitRef);
  }

  static Future<void> clearMarker(String loadId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(loadId));
  }
}