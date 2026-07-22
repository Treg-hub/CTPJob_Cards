import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart' as android_intent;
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
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

  /// Last successful permissions payload fingerprint (session dedupe).
  String? _lastPermissionsFingerprint;

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
      await Permission.locationAlways.request();
    }
    if ((await Permission.ignoreBatteryOptimizations.status).isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    if (!geofenceOnly) {
      await Permission.notification.request();
      await Permission.systemAlertWindow.request();
      await Permission.accessNotificationPolicy.request();
      await _recordFullScreenIntentGrant();
    }
  }

  /// Opens the Android settings screen (or app settings) for a single health key.
  Future<void> openSettingsFor(DeviceHealthKey key) async {
    if (kIsWeb) return;

    switch (key) {
      case DeviceHealthKey.ignoreBattery:
        if (defaultTargetPlatform == TargetPlatform.android) {
          const intent = android_intent.AndroidIntent(
            action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
          );
          await intent.launch();
        } else {
          await openAppSettings();
        }
      case DeviceHealthKey.notificationPolicy:
        if (defaultTargetPlatform == TargetPlatform.android) {
          const intent = android_intent.AndroidIntent(
            action: 'android.settings.NOTIFICATION_POLICY_ACCESS_SETTINGS',
          );
          await intent.launch();
        } else {
          await openAppSettings();
        }
      case DeviceHealthKey.locationAlways:
        if (!(await Permission.locationWhenInUse.status).isGranted) {
          await Permission.locationWhenInUse.request();
        }
        await Permission.locationAlways.request();
        if (!(await Permission.locationAlways.status).isGranted) {
          await openAppSettings();
        }
      case DeviceHealthKey.postNotifications:
        await Permission.notification.request();
        if (!(await Permission.notification.status).isGranted) {
          await openAppSettings();
        }
      case DeviceHealthKey.systemAlertWindow:
        await Permission.systemAlertWindow.request();
        if (!(await Permission.systemAlertWindow.status).isGranted) {
          await openAppSettings();
        }
      case DeviceHealthKey.fullScreenIntent:
        await _recordFullScreenIntentGrant();
        if (!(await _fullScreenIntentGranted())) {
          await openAppSettings();
        }
    }
  }

  /// Request dialogs, then open Settings for the first permission still denied.
  /// Returns true when all targeted checks pass after the flow.
  Future<bool> fixMissing({bool geofenceOnly = false}) async {
    if (kIsWeb) return true;

    await requestMissing(geofenceOnly: geofenceOnly);
    var snap = await check();
    final healthy =
        geofenceOnly ? snap.isGeofenceHealthy : snap.isFullyHealthy;
    if (healthy) return true;

    final missing = geofenceOnly
        ? snap.missing
            .where((k) =>
                k == DeviceHealthKey.locationAlways ||
                k == DeviceHealthKey.ignoreBattery)
            .toList()
        : snap.missing;
    if (missing.isNotEmpty) {
      await openSettingsFor(missing.first);
    }
    return false;
  }

  /// Fix a single permission — used by onboarding row taps.
  Future<void> fixPermission(Permission perm) async {
    if (kIsWeb) return;

    if (perm == Permission.locationAlways) {
      await openSettingsFor(DeviceHealthKey.locationAlways);
      return;
    }
    if (perm == Permission.ignoreBatteryOptimizations) {
      await openSettingsFor(DeviceHealthKey.ignoreBattery);
      return;
    }
    if (perm == Permission.notification) {
      await openSettingsFor(DeviceHealthKey.postNotifications);
      return;
    }
    if (perm == Permission.systemAlertWindow) {
      await openSettingsFor(DeviceHealthKey.systemAlertWindow);
      return;
    }
    if (perm == Permission.accessNotificationPolicy) {
      await openSettingsFor(DeviceHealthKey.notificationPolicy);
      return;
    }

    final status = await perm.status;
    if (!status.isGranted) {
      await perm.request();
      final after = await perm.status;
      if (!after.isGranted &&
          (after.isPermanentlyDenied || after.isDenied)) {
        await openAppSettings();
      }
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
  /// Skips when the payload matches the last successful sync this session.
  Future<void> syncPermissionsToFirestore({bool force = false}) async {
    if (kIsWeb) return;
    try {
      final payload = await permissionsPayloadForFirestore();
      final fingerprint = payload.entries
          .map((e) => '${e.key}:${(e.value as Map)['granted']}')
          .toList()
        ..sort();
      final key = fingerprint.join('|');
      if (!force && _lastPermissionsFingerprint == key) {
        debugPrint('syncPermissionsToFirestore skipped (unchanged)');
        return;
      }
      await FirestoreService().updateMyPresence(permissions: payload);
      _lastPermissionsFingerprint = key;
    } catch (e) {
      debugPrint('syncPermissionsToFirestore failed (non-fatal): $e');
    }
  }
}