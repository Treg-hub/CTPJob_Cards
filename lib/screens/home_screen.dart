import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;
import 'create_job_card_screen.dart';
import 'view_job_cards_screen.dart';
import 'my_assigned_jobs_screen.dart';
import 'completed_jobs_screen.dart';
import 'admin_screen.dart';
import 'manager_dashboard_screen.dart';
import 'job_card_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  bool isOnSite = true;

  // Responsive design helpers
  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  int get _gridCrossAxisCount {
    if (_isDesktop) return 4;
    if (_isTablet) return 3;
    return 2; // Mobile
  }

  double get _iconSize {
    if (_isDesktop) return 24;
    if (_isTablet) return 28;
    return 32; // Mobile
  }

  double get _cardPadding {
    if (_isDesktop) return 12;
    if (_isTablet) return 14;
    return 16; // Mobile
  }

  double get _screenPadding {
    if (_isDesktop) return 32;
    if (_isTablet) return 24;
    return 16; // Mobile
  }

  double get _gridSpacing {
    if (_isDesktop) return 16;
    if (_isTablet) return 14;
    return 12; // Mobile
  }

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
          // Mark notification as received/read
          _markNotificationReceived(message.data);
          if (mounted) {
            setState(() => _selectedIndex = 1); // Switch to Jobs tab
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

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_screenPadding),
      child: Column(
        children: [
          // Compact On-Site Toggle
          Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(_cardPadding),
              child: Row(
                children: [
                  Icon(
                    isOnSite ? Icons.check_circle : Icons.cancel,
                    color: isOnSite ? Colors.green : Colors.red,
                    size: _isDesktop ? 20 : 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isOnSite ? 'ON SITE – Ready for jobs' : 'OFF SITE – Notifications paused',
                      style: TextStyle(
                        fontSize: _isDesktop ? 14 : 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: _isDesktop ? 0.7 : 0.8,
                    child: Switch(
                      value: isOnSite,
                      onChanged: _toggleOnSite,
                      activeColor: Colors.green,
                      inactiveTrackColor: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: _isDesktop ? 32 : 24),

          // Quick Actions Grid
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: _isDesktop ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: _isDesktop ? 20 : 16),
          GridView.count(
            crossAxisCount: _gridCrossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: _gridSpacing,
            mainAxisSpacing: _gridSpacing,
            children: [
              _buildQuickActionCard(
                'Create Job Card',
                Icons.add_circle,
                const Color(0xFFFF8C42),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen())),
              ),
              _buildQuickActionCard(
                'View Open Jobs',
                Icons.list_alt,
                const Color(0xFF64748B),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen())),
              ),
              _buildQuickActionCard(
                'My Assigned Jobs',
                Icons.assignment_turned_in,
                const Color(0xFF10B981),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAssignedJobsScreen())),
              ),
              _buildQuickActionCard(
                'Completed Jobs',
                Icons.history,
                const Color(0xFF8B5CF6),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompletedJobsScreen())),
              ),
            ],
          ),

          SizedBox(height: _isDesktop ? 32 : 24),

          // Management & Administration Section
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Management & Administration',
                style: TextStyle(
                  fontSize: _isDesktop ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: _isDesktop ? 20 : 16),
              if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickActionCard(
                        'Manager Dashboard',
                        Icons.dashboard,
                        const Color(0xFFEF4444),
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerDashboardScreen())),
                      ),
                    ),
                    SizedBox(width: _gridSpacing),
                    Expanded(
                      child: _buildQuickActionCard(
                        'Admin Settings',
                        Icons.settings,
                        const Color(0xFF14B8A6),
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                      ),
                    ),
                  ],
                )
              else
                _buildQuickActionCard(
                  'Admin Settings',
                  Icons.settings,
                  const Color(0xFF14B8A6),
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                  fullWidth: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color, VoidCallback onTap, {bool fullWidth = false}) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(_cardPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: _iconSize, color: color),
              SizedBox(height: _isDesktop ? 6 : 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: _isDesktop ? 12 : 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobsTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Open Jobs'),
              Tab(text: 'All Jobs'),
            ],
            labelColor: Color(0xFFFF8C42),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFFF8C42),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildOpenJobsList(),
                _buildAllJobsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenJobsList() {
    return StreamBuilder(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final jobCards = snapshot.data!.where((job) => job.status != JobStatus.completed).toList();

        if (jobCards.isEmpty) {
          return const Center(
            child: Text('No open jobs available', style: TextStyle(color: Colors.white70)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: jobCards.length,
          itemBuilder: (context, index) {
            final job = jobCards[index];
            return Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Priority: P${job.priority} • Type: ${job.type.displayName}',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityColor('P${job.priority}'),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'P${job.priority}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                onTap: () {
                  // Navigate to job details - for now just show a snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tapped on: ${job.description}')),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAllJobsList() {
    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final jobCards = snapshot.data!;

        if (jobCards.isEmpty) {
          return const Center(
            child: Text('No jobs available', style: TextStyle(color: Colors.white70)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: jobCards.length,
          itemBuilder: (context, index) {
            final job = jobCards[index];
            return Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority: P${job.priority} • Type: ${job.type.displayName}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Status: ${job.status.displayName}',
                      style: TextStyle(
                        color: _getStatusColor(job.status.name),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityColor('P${job.priority}'),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'P${job.priority}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                onTap: () {
                  // Navigate to job details - for now just show a snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tapped on: ${job.description}')),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'P1':
        return Colors.red;
      case 'P2':
        return Colors.orange;
      case 'P3':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildMyWorkTab() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Assigned'),
              Tab(text: 'Created'),
              Tab(text: 'History'),
            ],
            labelColor: Color(0xFFFF8C42),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFFF8C42),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAssignedJobs(),
                _buildCreatedJobs(),
                _buildWorkHistory(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedJobs() {
    if (currentEmployee == null) {
      return const Center(
        child: Text('Please log in to view assigned jobs', style: TextStyle(color: Colors.white70)),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAssignedJobCards(currentEmployee!.clockNo),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final assignedJobs = snapshot.data!;

        if (assignedJobs.isEmpty) {
          return const Center(
            child: Text('No jobs assigned to you', style: TextStyle(color: Colors.white70)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: assignedJobs.length,
          itemBuilder: (context, index) {
            final job = assignedJobs[index];
            return Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority: P${job.priority} • Type: ${job.type.displayName}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Status: ${job.status.displayName} • From: ${job.operator}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityColor('P${job.priority}'),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'P${job.priority}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JobCardDetailScreen(jobCard: job),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCreatedJobs() {
    if (currentEmployee == null) {
      return const Center(
        child: Text('Please log in to view created jobs', style: TextStyle(color: Colors.white70)),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final createdJobs = snapshot.data!
            .where((job) => job.operatorClockNo == currentEmployee!.clockNo)
            .toList();

        if (createdJobs.isEmpty) {
          return const Center(
            child: Text('No jobs created by you', style: TextStyle(color: Colors.white70)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: createdJobs.length,
          itemBuilder: (context, index) {
            final job = createdJobs[index];
            return Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority: P${job.priority} • Type: ${job.type.displayName}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Status: ${job.status.displayName}',
                      style: TextStyle(
                        color: _getStatusColor(job.status.name),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPriorityColor('P${job.priority}'),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'P${job.priority}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JobCardDetailScreen(jobCard: job),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWorkHistory() {
    if (currentEmployee == null) {
      return const Center(
        child: Text('Please log in to view work history', style: TextStyle(color: Colors.white70)),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getCompletedJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final completedJobs = snapshot.data!
            .where((job) => job.completedBy == currentEmployee!.clockNo)
            .toList();

        if (completedJobs.isEmpty) {
          return const Center(
            child: Text('No completed work history', style: TextStyle(color: Colors.white70)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: completedJobs.length,
          itemBuilder: (context, index) {
            final job = completedJobs[index];
            return Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority: P${job.priority} • Type: ${job.type.displayName}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Completed: ${job.completedAt != null ? _formatDate(job.completedAt!) : 'Unknown'}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                trailing: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 24,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JobCardDetailScreen(jobCard: job),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: _isDesktop ? 22 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: _isDesktop ? 32 : 24),

          // User Info
          Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(_cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current User: ${currentEmployee?.name ?? 'Unknown'}',
                    style: TextStyle(
                      fontSize: _isDesktop ? 14 : 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Clock No: ${currentEmployee?.clockNo ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Department: ${currentEmployee?.department ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: _isDesktop ? 32 : 24),

          // Developer Options (only show if not web)
          if (!kIsWeb) ...[
            Text(
              'Developer Options',
              style: TextStyle(
                fontSize: _isDesktop ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: _isDesktop ? 20 : 16),
            ElevatedButton.icon(
              onPressed: () async {
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
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh FCM Token'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _markNotificationReceived(Map<String, dynamic> data) async {
    try {
      // Extract job card ID from notification data
      final jobCardId = data['jobCardId'];
      if (jobCardId == null) return;

      // Get the current job card
      final jobCard = await _firestoreService.getJobCard(jobCardId);
      if (jobCard == null) return;

      // Only update if notification hasn't been received yet and user is the assigned person
      if (jobCard.notificationReceivedAt == null && jobCard.assignedTo == currentEmployee?.clockNo) {
        final updatedJob = jobCard.copyWith(
          notificationReceivedAt: DateTime.now(),
        );
        await _firestoreService.updateJobCard(jobCardId, updatedJob);
      }
    } catch (e) {
      debugPrint('Error marking notification as received: $e');
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          _buildJobsTab(),
          _buildMyWorkTab(),
          _buildSettingsTab(),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 ? FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen())),
        backgroundColor: const Color(0xFFFF8C42),
        child: const Icon(Icons.add, color: Colors.black),
      ) : null,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.work),
            label: 'Jobs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'My Work',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFFF8C42),
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1A1A1A),
        onTap: _onItemTapped,
      ),
    );
  }
}



