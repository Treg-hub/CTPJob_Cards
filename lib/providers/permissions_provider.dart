import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart' show currentEmployee;
import '../services/device_health_service.dart';


class PermissionItem {
  final Permission? permission;
  final DeviceHealthKey? healthKey;
  final String title;
  final String description;
  final String whyNeeded;
  final IconData icon;

  const PermissionItem({
    this.permission,
    this.healthKey,
    required this.title,
    required this.description,
    required this.whyNeeded,
    required this.icon,
  }) : assert(permission != null || healthKey != null);
}

final requiredPermissionsProvider = Provider<List<PermissionItem>>((ref) {
  return const [
    PermissionItem(
      permission: Permission.notification,
      healthKey: DeviceHealthKey.postNotifications,
      title: 'Notifications',
      description: 'Real-time job alerts that bypass Do Not Disturb & silence',
      whyNeeded:
          'Get instant push notifications even when your phone is on silent or Do Not Disturb. Never miss urgent job cards while onsite.',
      icon: Icons.notifications_active_outlined,
    ),
    PermissionItem(
      permission: Permission.locationAlways,
      healthKey: DeviceHealthKey.locationAlways,
      title: 'Location (Always)',
      description: 'Job site tracking & geofencing 24/7',
      whyNeeded:
          'Required so you receive notifications and alerts while you are physically onsite. This is essential for accurate job tracking.',
      icon: Icons.location_on_outlined,
    ),
    PermissionItem(
      permission: Permission.ignoreBatteryOptimizations,
      healthKey: DeviceHealthKey.ignoreBattery,
      title: 'Battery optimisation off',
      description: 'Keeps geofencing and alerts alive in the background',
      whyNeeded:
          'Aggressive battery savers stop background location and push delivery. Unrestricted battery is required on many phones.',
      icon: Icons.battery_saver_outlined,
    ),
    PermissionItem(
      permission: Permission.camera,
      title: 'Camera',
      description: 'Attach photos to job cards',
      whyNeeded:
          'Capture before/after photos directly in the app as evidence for completed work. Improves reporting quality.',
      icon: Icons.camera_alt_outlined,
    ),
    PermissionItem(
      permission: Permission.systemAlertWindow,
      healthKey: DeviceHealthKey.systemAlertWindow,
      title: 'Display over other apps',
      description: 'Full-screen job alerts',
      whyNeeded:
          'Show important job alerts on top of whatever app you are using — critical for urgent onsite notifications.',
      icon: Icons.fullscreen_outlined,
    ),
    PermissionItem(
      permission: Permission.accessNotificationPolicy,
      healthKey: DeviceHealthKey.notificationPolicy,
      title: 'Do Not Disturb access',
      description: 'P4/P5 alerts through silent mode',
      whyNeeded:
          'Lets priority 4 and 5 job alerts reach you when the phone is on Do Not Disturb.',
      icon: Icons.do_not_disturb_on_outlined,
    ),
  ];
});

class PermissionsNotifier extends AsyncNotifier<Map<Permission, PermissionStatus>> {
  @override
  Future<Map<Permission, PermissionStatus>> build() async {
    final items = ref.read(requiredPermissionsProvider);
    final Map<Permission, PermissionStatus> statusMap = {};
    for (final item in items) {
      final perm = item.permission;
      if (perm != null) {
        statusMap[perm] = await perm.status;
      }
    }
    return statusMap;
  }

  Future<void> requestPermission(Permission perm) async {
    await perm.request();

    if (currentEmployee != null) {
      await DeviceHealthService().syncPermissionsToFirestore();
    }

    ref.invalidateSelf();
  }

  Future<void> openAppSettingsForPermission() async {
    await openAppSettings();
  }
}

final permissionsProvider =
    AsyncNotifierProvider<PermissionsNotifier, Map<Permission, PermissionStatus>>(
  () => PermissionsNotifier(),
);