import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart' as android_intent;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' show currentEmployee;
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/location_service.dart';
import 'admin_screen.dart';
import 'notification_diagnostics_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool isOnSite = true;

  @override
  void initState() {
    super.initState();
    _loadOnSiteStatus();
    _initializeLocalNotifications();
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _localNotifications.initialize(settings: initializationSettings);
  }

  Future<void> _loadOnSiteStatus() async {
    if (currentEmployee == null) return;
    try {
      final emp = await _firestoreService.getEmployee(currentEmployee!.clockNo);
      if (emp != null && mounted) {
        setState(() => isOnSite = emp.isOnSite);
      }
    } catch (_) {}
  }

  Future<void> _testFullScreenAlert() async {
    try {
      await _notificationService.showOnSiteNotification(
        title: "🚨 FULL SCREEN ALERT TEST",
        body: "Priority 5 full-screen takeover test — this should bypass DND and take over the screen.",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Full-screen alert triggered! (Check lock screen / DND bypass)'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testPersistentNotification() async {
    try {
      await _notificationService.showOnSiteNotification(
        title: "PERSISTENT NOTIFICATION TEST",
        body: "This is a persistent banner test (P4/P5 style with action buttons).",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Persistent banner triggered! Pull down notification shade.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testGeneralNotification() async {
  try {
    await _localNotifications.show(
      id: 9999,
      title: 'General Notification Test',
      body: 'This is a standard job alert test from Settings.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'normal_channel',
          'Normal Job Notifications',
          channelDescription: 'Standard notifications for job card assignments',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ General notification triggered! Check your notification shade.'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

  Widget _buildPermissionTile(String title, bool isGranted, String permKey) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isGranted ? Icons.check_circle : Icons.cancel,
          color: isGranted ? Colors.green : Colors.red,
          size: 28,
        ),
        title: Text(title),
        subtitle: Text(isGranted ? 'Approved ✓' : 'Not approved — tap to fix'),
        trailing: isGranted
            ? null
            : ElevatedButton(
                onPressed: () async {
                  if (permKey == 'notification_policy' && Platform.isAndroid) {
                    final intent = android_intent.AndroidIntent(
                      action: 'android.settings.NOTIFICATION_POLICY_ACCESS_SETTINGS',
                    );
                    await intent.launch();
                  } else if (permKey == 'ignore_battery' && Platform.isAndroid) {
                    final intent = android_intent.AndroidIntent(
                      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
                    );
                    await intent.launch();
                  } else {
                    await openAppSettings();
                  }
                  if (mounted) setState(() {});
                },
                child: const Text('Open Settings'),
              ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Out')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          _locationService.stopNativeMonitoring();
        } else if (kIsWeb) {
          debugPrint('📍 Geofencing stop skipped on web platform');
        }
        await _firestoreService.clearLoggedInEmployee();
        currentEmployee = null;
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error logging out: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = currentEmployee?.clockNo == '22';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromRGBO(255, 140, 66, 1), Color.fromARGB(255, 124, 124, 124)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current User', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    currentEmployee?.name ?? 'Unknown',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Clock No: ${currentEmployee?.clockNo ?? '—'}'),
                  Text('Department: ${currentEmployee?.department ?? '—'}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(isOnSite ? Icons.check_circle : Icons.cancel, color: isOnSite ? Colors.green : Colors.red),
                      const SizedBox(width: 8),
                      Text(isOnSite ? 'ON SITE – Ready for jobs' : 'OFF SITE – Notifications paused'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Checking for updates...'), duration: Duration(seconds: 1)),
                    );
                    try {
                      await UpdateService().forceCheckForUpdate(context);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.system_update),
                  label: const Text('Check for Update'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C42),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refreshing FCM token...'), duration: Duration(seconds: 1)),
                    );
                    try {
                      await _notificationService.refreshToken();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ FCM Token refreshed!'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh FCM Token'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('App Permissions Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, bool>>(
            future: _notificationService.checkAllCriticalPermissions(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Card(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
              }
              final perms = snapshot.data!;
              return Column(
                children: [
                  _buildPermissionTile('Notifications', perms['post_notifications'] ?? false, 'notification'),
                  _buildPermissionTile('Display over other apps (Full-screen)', perms['system_alert_window'] ?? false, 'system_alert_window'),
                  _buildPermissionTile('DND / Notification Policy', perms['notification_policy'] ?? false, 'notification_policy'),
                  _buildPermissionTile('Ignore Battery Optimization', perms['ignore_battery'] ?? false, 'ignore_battery'),
                  _buildPermissionTile('Location (Always)', true, 'location'),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Notification Tests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fullscreen, color: Colors.red, size: 28),
              title: const Text('1. Full Screen Alert Test'),
              subtitle: const Text('Priority 5 full-screen takeover (bypasses DND)'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: _testFullScreenAlert,
                child: const Text('TEST'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active, color: Colors.orange, size: 28),
              title: const Text('2. Persistent Notification'),
              subtitle: const Text('Red persistent banner with action buttons'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                onPressed: _testPersistentNotification,
                child: const Text('TEST'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications, color: Colors.blue, size: 28),
              title: const Text('3. General Notification'),
              subtitle: const Text('Standard job assignment / alert'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: _testGeneralNotification,
                child: const Text('TEST'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (isAdmin) ...[
            const Text('Admin (Clock 22)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings, color: Color(0xFF14B8A6)),
                title: const Text('Manage Collections'),
                subtitle: const Text('Firestore admin tools, migrations, employees'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.purple),
                title: const Text('Notification Diagnostics'),
                subtitle: const Text('Advanced fullscreen & permission testing'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationDiagnosticsScreen())),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Log Out'),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }
}