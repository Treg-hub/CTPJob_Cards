import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart' as android_intent;


import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show currentEmployee;
import '../providers/theme_provider.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/location_service.dart';
import '../utils/role.dart' show isAdmin;
import 'admin_screen.dart';
import 'documentation_screen.dart';
import 'notification_diagnostics_screen.dart';
import 'notification_inbox_screen.dart';
import 'notification_test_screen.dart';
import 'login_screen.dart';
import '../widgets/reset_permissions_button.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  final FirestoreService _firestoreService = FirestoreService();
  final LocationService _locationService = LocationService();
  bool isOnSite = true;
  Stream<QuerySnapshot>? _inboxStream;

  @override
  void initState() {
    super.initState();
    _loadOnSiteStatus();
    _initializeLocalNotifications();
    _setupInboxStream();
  }

  void _setupInboxStream() {
    final clockNo = currentEmployee?.clockNo;
    if (clockNo == null) return;
    _inboxStream = FirebaseFirestore.instance
        .collection('notification_inbox')
        .doc(clockNo)
        .collection('items')
        .where('read', isEqualTo: false)
        .snapshots();
  }

  Future<void> _initializeLocalNotifications() async {
    await NotificationService().initialize();
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
                  if (permKey == 'notification_policy' && defaultTargetPlatform == TargetPlatform.android) {
                    const intent = android_intent.AndroidIntent(
                      action: 'android.settings.NOTIFICATION_POLICY_ACCESS_SETTINGS',
                    );
                    await intent.launch();
                  } else if (permKey == 'ignore_battery' && defaultTargetPlatform == TargetPlatform.android) {
                    const intent = android_intent.AndroidIntent(
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
        if (!kIsWeb) {
          _locationService.stopNativeMonitoring();
        } else if (kIsWeb) {
          debugPrint('📍 Geofencing stop skipped on web platform');
        }
        await _firestoreService.clearLoggedInEmployee();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('permissionsCompleted');
        if (!kIsWeb) await FirebaseCrashlytics.instance.setUserIdentifier('');
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
    final bool isAdminUser = isAdmin(currentEmployee);
    final themeMode = ref.watch(themeNotifierProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFFF8C42), isOnSite ? Colors.green : Colors.red],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _inboxStream,
        builder: (context, inboxSnap) {
          final unreadCount = inboxSnap.data?.docs.length ?? 0;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [

              // ── Your Profile ─────────────────────────────────────
              _SectionHeader('Your Profile'),
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current User', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text(
                        currentEmployee?.name ?? 'Unknown',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('Clock No: ${currentEmployee?.clockNo ?? '—'}'),
                      Text('Department: ${currentEmployee?.department ?? '—'}'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(isOnSite ? Icons.check_circle : Icons.cancel,
                              color: isOnSite ? Colors.green : Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            isOnSite ? 'ON SITE – Ready for jobs' : 'OFF SITE – Notifications paused',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isOnSite ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.menu_book, color: Color(0xFFFF8C42)),
                  title: const Text('Documentation'),
                  subtitle: const Text('Guides, references, and troubleshooting'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentationScreen())),
                ),
              ),

              // ── Preferences ──────────────────────────────────────
              const SizedBox(height: 16),
              _SectionHeader('Preferences'),
              Card(
                elevation: 2,
                child: SwitchListTile(
                  secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: const Color(0xFFFF8C42)),
                  title: const Text('Dark Mode'),
                  subtitle: Text(isDark ? 'Switch to light theme' : 'Switch to dark theme'),
                  value: isDark,
                  activeThumbColor: const Color(0xFFFF8C42),
                  onChanged: (_) => ref.read(themeNotifierProvider.notifier).toggleTheme(),
                ),
              ),

              // ── Notifications ─────────────────────────────────────
              const SizedBox(height: 16),
              _SectionHeader('Notifications'),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: unreadCount > 0
                      ? Badge(
                          label: Text('$unreadCount'),
                          child: const Icon(Icons.notifications_outlined, color: Color(0xFFFF8C42)),
                        )
                      : const Icon(Icons.notifications_outlined, color: Color(0xFFFF8C42)),
                  title: const Text('Notification Inbox'),
                  subtitle: Text(unreadCount > 0
                      ? '$unreadCount unread — received while offsite'
                      : 'No unread notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationInboxScreen())),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.science_outlined, color: Colors.blueGrey),
                  title: const Text('Notification Tests'),
                  subtitle: const Text('Test full-screen, persistent, and general alerts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationTestScreen())),
                ),
              ),

              // ── App & Connectivity ────────────────────────────────
              const SizedBox(height: 16),
              _SectionHeader('App & Connectivity'),
              const ResetPermissionsButton(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Checking for updates...'), duration: Duration(seconds: 1)),
                        );
                        try {
                          await UpdateService().forceCheckForUpdate(context);
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
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
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Refreshing FCM token...'), duration: Duration(seconds: 1)),
                        );
                        try {
                          await _notificationService.refreshToken();
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('FCM Token refreshed'), backgroundColor: Colors.green),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
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

              // ── App Permissions ───────────────────────────────────
              if (!kIsWeb) ...[
                const SizedBox(height: 16),
                _SectionHeader('App Permissions'),
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
              ],

              // ── Admin ────────────────────────────────────────────
              if (isAdminUser) ...[
                const SizedBox(height: 16),
                _SectionHeader('Admin'),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber.shade300, width: 1),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.amber.shade50.withValues(alpha: isDark ? 0.05 : 1.0),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings, color: Color(0xFF14B8A6)),
                        title: const Text('Admin Settings'),
                        subtitle: const Text('Employees, structures, escalation config, job cards'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.bug_report, color: Colors.purple),
                        title: const Text('Notification Diagnostics'),
                        subtitle: const Text('Advanced fullscreen & permission testing'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationDiagnosticsScreen())),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Account ───────────────────────────────────────────
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Log Out'),
                  onTap: _logout,
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF757575),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}