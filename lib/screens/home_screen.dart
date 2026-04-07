import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;
import 'create_job_card_screen.dart';
import 'view_job_cards_screen.dart';
import 'my_assigned_jobs_screen.dart';
import 'completed_jobs_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isOnSite = true;

  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadOnSiteStatus();
    if (!kIsWeb) _setupFirebaseMessaging();
  }

  Future<void> _setupFirebaseMessaging() async {
    try {
      await _notificationService.initialize();
      FirebaseMessaging.onMessage.listen((message) {
        if (message.notification != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message.notification!.body ?? 'New notification'),
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFFFF8C42),
            ),
          );
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data['click_action'] == 'FLUTTER_NOTIFICATION_CLICK') {
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAssignedJobsScreen()));
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error setting up Firebase Messaging: $e');
    }
  }

  Future<void> _loadOnSiteStatus() async {
    if (currentEmployee == null) return;
    try {
      final emp = await _firestoreService.getEmployee(currentEmployee!.clockNo);
      if (emp != null) {
        setState(() => isOnSite = emp.isOnSite);
      }
    } catch (e) {
      debugPrint('Error loading on-site status: $e');
    }
  }

  Future<void> _toggleOnSite(bool value) async {
    setState(() => isOnSite = value);
    if (currentEmployee == null) return;

    try {
      final updatedEmployee = currentEmployee!.copyWith(isOnSite: value);
      await _firestoreService.updateEmployee(updatedEmployee);
      currentEmployee = updatedEmployee;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
        );
      }
      // Revert the UI change
      setState(() => isOnSite = !value);
    }
  }

  Future<void> _refreshFcmToken() async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Push notifications are for mobile only'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    try {
      await _notificationService.refreshToken();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ FCM Token refreshed successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error refreshing token: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change User Account'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Enter password', hintText: '••••••'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final password = passwordController.text.trim();
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter password'), backgroundColor: Colors.red),
                );
                return;
              }

              try {
                final correctPassword = await _firestoreService.getSwitchUserPassword();
                if (password != correctPassword) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  _showUserSwitchDialog(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  void _showUserSwitchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch User'),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<List<Employee>>(
            stream: _firestoreService.getEmployeesStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final employees = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                itemCount: employees.length,
                itemBuilder: (context, index) {
                  final emp = employees[index];
                  return ListTile(
                    title: Text(emp.displayName),
                    onTap: () async {
                      try {
                        // Save new employee to shared preferences
                        await _firestoreService.saveLoggedInEmployee(emp.clockNo);

                        // Update FCM token for new employee
                        if (!kIsWeb) {
                          try {
                            final token = await _notificationService.getToken();
                            if (token != null) {
                              await _firestoreService.updateEmployee(
                                emp.copyWith(fcmToken: token, fcmTokenUpdatedAt: DateTime.now()),
                              );
                            }
                          } catch (e) {
                            debugPrint('Error updating FCM token: $e');
                          }
                        }

                        setState(() => currentEmployee = emp);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Switched to ${emp.name}'), backgroundColor: Colors.green),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error switching user: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, String title, Color color, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        label: Text(title),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showPasswordDialog(context),
          child: const Text('CTP Job Cards'),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8C42), Color.fromARGB(255, 124, 124, 124)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                currentEmployee?.name ?? 'User',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _toggleOnSite(!isOnSite),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isOnSite ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isOnSite ? Icons.check_circle : Icons.cancel,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isOnSite ? 'ON SITE – Ready for jobs' : 'OFF SITE – Notifications paused',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Transform.scale(
                        scale: 1.2,
                        child: Switch(
                          value: isOnSite,
                          onChanged: _toggleOnSite,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color.fromARGB(255, 20, 128, 78),
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshFcmToken,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh FCM Token'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
              const SizedBox(height: 32),
              Image.asset('assets/images/logo.png', width: 200, height: 200, fit: BoxFit.cover),
              const SizedBox(height: 24),
              const SizedBox(height: 48),
              _buildMenuButton(
                context,
                'Create New Job Card',
                const Color(0xFFFF8C42),
                Icons.add_circle,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen())),
              ),
              const SizedBox(height: 12),
              _buildMenuButton(
                context,
                'View Open Job Cards',
                const Color(0xFF64748B),
                Icons.list_alt,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen())),
              ),
              const SizedBox(height: 12),
              _buildMenuButton(
                context,
                'My Assigned Jobs',
                const Color(0xFF10B981),
                Icons.assignment_turned_in,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAssignedJobsScreen())),
              ),
              const SizedBox(height: 12),
              _buildMenuButton(
                context,
                'Completed Jobs History',
                const Color(0xFF8B5CF6),
                Icons.history,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompletedJobsScreen())),
              ),
              const SizedBox(height: 12),
              _buildMenuButton(
                context,
                'Admin Settings',
                const Color(0xFF14B8A6),
                Icons.settings,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
