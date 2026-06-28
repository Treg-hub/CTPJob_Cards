import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_service.dart';
import 'notification_service.dart';

/// Keys stored on `employees.permissions` via updateEmployeePresence.
enum DeviceHealthKey {
  locationAlways,
  ignoreBattery,
  postNotifications,
  notificationPolicy,
  systemAlertWindow,
  fullScreenIntent,
}

extension DeviceHealthKeyExt on DeviceHealthKey {
  String get storageKey => name;

  String get label => switch (this) {
        DeviceHealthKey.locationAlways => 'Location “Allow all the time”',
        DeviceHealthKey.ignoreBattery => 'Battery optimisation off',
        DeviceHealthKey.postNotifications => 'Notifications',
        DeviceHealthKey.notificationPolicy => 'Do Not Disturb access',
        DeviceHealthKey.systemAlertWindow => 'Display over other apps',
        DeviceHealthKey.fullScreenIntent => 'Full-screen alerts (P5)',
      };
}

/// Snapshot of the six Android-critical permission checks.
class DeviceHealthSnapshot {
  final Map<DeviceHealthKey, bool> granted;

  const DeviceHealthSnapshot(this.granted);

  bool isGranted(DeviceHealthKey key) => granted[key] ?? false;

  bool get isGeofenceHealthy =>
      isGranted(DeviceHealthKey.locationAlways) &&
      isGranted(DeviceHealthKey.ignoreBattery);

  /// Core trio required for onboarding completion without override.
  bool get isOnboardingCoreHealthy =>
      isGeofenceHealthy && isGranted(DeviceHealthKey.postNotifications);

  bool get isFullyHealthy =>
      DeviceHealthKey.values.every((k) => isGranted(k));

  List<DeviceHealthKey> get missing =>
      DeviceHealthKey.values.where((k) => !isGranted(k)).toList();

  List<String> get missingLabels =>
      missing.map((k) => k.label).toList();

  /// For admin display from Firestore `employees.permissions` map.
  static DeviceHealthSnapshot? fromFirestorePermissions(
      Map<String, dynamic>? permissions) {
    if (permissions == null || permissions.isEmpty) return null;
    final granted = <DeviceHealthKey, bool>{};
    for (final key in DeviceHealthKey.values) {
      final entry = permissions[key.storageKey];
      if (entry is Map) {
        granted[key] = entry['granted'] == true;
      }
    }
    if (granted.isEmpty) return null;
    for (final key in DeviceHealthKey.values) {
      granted.putIfAbsent(key, () => false);
    }
    return DeviceHealthSnapshot(granted);
  }

  bool get hasAnyDenied =>
      granted.values.any((v) => !v);

  bool get isAllGrantedInFirestore =>
      DeviceHealthKey.values.every((k) => isGranted(k));
}

class DeviceHealthService {
  static final DeviceHealthService _instance = DeviceHealthService._internal();
  factory DeviceHealthService() => _instance;
  DeviceHealthService._internal();

  final NotificationService _notificationService = NotificationService();

  static const _fullScreenIntentPrefsKey = 'deviceHealth_fullScreenIntent';

  Future<bool> _fullScreenIntentGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_fullScreenIntentPrefsKey)) {
      return prefs.getBool(_fullScreenIntentPrefsKey) ?? false;
    }
    // Plugin v21 has no stable read API — overlay grant is a reasonable proxy
    // until the user runs a guided Fix flow.
    return Permission.systemAlertWindow.isGranted;
  }

  Future<void> _recordFullScreenIntentGrant() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted =
          await plugin?.requestFullScreenIntentPermission() ?? true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_fullScreenIntentPrefsKey, granted);
    } catch (e) {
      debugPrint('fullScreenIntent request failed (non-fatal): $e');
    }
  }

  Future<DeviceHealthSnapshot> check() async {
    if (kIsWeb) {
      return DeviceHealthSnapshot({
        for (final k in DeviceHealthKey.values) k: true,
      });
    }

    final notifPerms = await _notificationService.checkAllCriticalPermissions();
    final locationAlways = await Permission.locationAlways.isGranted;
    final fullScreen = await _fullScreenIntentGranted();

    return DeviceHealthSnapshot({
      DeviceHealthKey.locationAlways: locationAlways,
      DeviceHealthKey.ignoreBattery:
          notifPerms['ignore_battery'] ?? false,
      DeviceHealthKey.postNotifications:
          notifPerms['post_notifications'] ?? false,
      DeviceHealthKey.notificationPolicy:
          notifPerms['notification_policy'] ?? false,
      DeviceHealthKey.systemAlertWindow:
          notifPerms['system_alert_window'] ?? false,
      DeviceHealthKey.fullScreenIntent: fullScreen,
    });
  }

  Future<void> requestMissing({bool geofenceOnly = false}) async {
    if (kIsWeb) return;

    if (!(await Permission.locationWhenInUse.status).isGranted) {
      await Permission.locationWhenInUse.request();
    }
    if (!(await Permission.locationAlways.status).isGranted) {
      final res = await Permission.locationAlways.request();
      final always = await Permission.locationAlways.status;
      if (!res.isGranted &&
          (res.isPermanentlyDenied || always.isPermanentlyDenied)) {
        await openAppSettings();
      }
    }
    if ((await Permission.ignoreBatteryOptimizations.status).isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    if (!geofenceOnly) {
      await _notificationService.requestAllCriticalPermissions();
      await _recordFullScreenIntentGrant();
    }
  }

  Future<Map<String, dynamic>> permissionsPayloadForFirestore() async {
    final snapshot = await check();
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      for (final key in DeviceHealthKey.values)
        key.storageKey: {
          'granted': snapshot.isGranted(key),
          'grantedAt': now,
          'version': 1,
        },
    };
  }

  /// Best-effort sync of all permission statuses to employees.permissions.
  Future<void> syncPermissionsToFirestore() async {
    if (kIsWeb) return;
    try {
      final payload = await permissionsPayloadForFirestore();
      await FirestoreService().updateMyPresence(permissions: payload);
    } catch (e) {
      debugPrint('syncPermissionsToFirestore failed (non-fatal): $e');
    }
  }
}