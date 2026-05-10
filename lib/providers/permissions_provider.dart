import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show currentEmployee;

class PermissionItem {
  final Permission permission;
  final String title;
  final String description;
  final String whyNeeded;
  final IconData icon;

  const PermissionItem({
    required this.permission,
    required this.title,
    required this.description,
    required this.whyNeeded,
    required this.icon,
  });
}

final requiredPermissionsProvider = Provider<List<PermissionItem>>((ref) {
  return const [
    PermissionItem(
      permission: Permission.notification,
      title: 'Notifications',
      description: 'Real-time job alerts that bypass Do Not Disturb & silence',
      whyNeeded: 'Get instant push notifications even when your phone is on silent or Do Not Disturb. Never miss urgent job cards while onsite.',
      icon: Icons.notifications_active_outlined,
    ),
    PermissionItem(
      permission: Permission.locationAlways,
      title: 'Location (Always)',
      description: 'Job site tracking & geofencing 24/7',
      whyNeeded: 'Required so you receive notifications and alerts while you are physically onsite. This is essential for accurate job tracking.',
      icon: Icons.location_on_outlined,
    ),
    PermissionItem(
      permission: Permission.camera,
      title: 'Camera',
      description: 'Attach photos to job cards',
      whyNeeded: 'Capture before/after photos directly in the app as evidence for completed work. Improves reporting quality.',
      icon: Icons.camera_alt_outlined,
    ),
    PermissionItem(
      permission: Permission.systemAlertWindow,
      title: 'Display over other apps',
      description: 'Full-screen job alerts',
      whyNeeded: 'Show important job alerts on top of whatever app you’re using — critical for urgent onsite notifications.',
      icon: Icons.fullscreen_outlined,
    ),
  ];
});

class PermissionsNotifier extends AsyncNotifier<Map<Permission, PermissionStatus>> {
  @override
  Future<Map<Permission, PermissionStatus>> build() async {
    final items = ref.read(requiredPermissionsProvider);
    final Map<Permission, PermissionStatus> statusMap = {};
    for (final item in items) {
      statusMap[item.permission] = await item.permission.status;
    }
    return statusMap;
  }

  Future<void> requestPermission(Permission perm) async {
    final status = await perm.request();
    
    final emp = currentEmployee;
    if (emp != null) {
      try {
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(emp.clockNo)
            .set({
          'permissions': {
            perm.toString(): {
              'granted': status.isGranted,
              'grantedAt': FieldValue.serverTimestamp(),
              'version': 1,
            }
          }
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore permission save error: $e');
      }
    }

    ref.invalidateSelf();
  }

  Future<void> openAppSettingsForPermission() async {
    await openAppSettings();
  }
}

final permissionsProvider = AsyncNotifierProvider<PermissionsNotifier, Map<Permission, PermissionStatus>>(
  () => PermissionsNotifier(),
);