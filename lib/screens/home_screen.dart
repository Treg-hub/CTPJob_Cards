import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'monitoring_dashboard_screen.dart';
import 'copper_storage_screen.dart';

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
  String? _pendingJobId;
  bool _showDeptOnly = true;
  int _openJobCount = 0;
  StreamSubscription<List<JobCard>>? _countSubscription;

  // Responsive design helpers
  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  // Role helpers
  bool get isManager => currentEmployee?.position.toLowerCase().contains('manager') ?? false;
  bool get isTechnician => (currentEmployee?.position.toLowerCase().contains('mechanical') ?? false) ||
                           (currentEmployee?.position.toLowerCase().contains('electrical') ?? false);
  bool get isOperator => !(isManager || isTechnician);
  bool get isSuperManager => currentEmployee?.department.toLowerCase() == 'general';

  bool get _isCopperAuthorized => ['22', '5421', '20'].contains(currentEmployee?.clockNo ?? '');

  List<Map<String, dynamic>> get _quickActions {
    final actions = [
      {'title': 'Create Job Card', 'icon': Icons.add_circle, 'color': const Color(0xFFFF8C42), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen()))},
      {'title': 'View Open Jobs', 'icon': Icons.list_alt, 'color': const Color(0xFF64748B), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()))},
      {'title': 'My Assigned Jobs', 'icon': Icons.assignment_turned_in, 'color': const Color(0xFF10B981), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAssignedJobsScreen()))},
      {'title': 'Completed Jobs', 'icon': Icons.history, 'color': const Color(0xFF8B5CF6), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompletedJobsScreen()))},
    ];

    final monitoringAction = {'title': 'Monitoring Dashboard', 'icon': Icons.dashboard, 'color': const Color(0xFFFFA500), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonitoringDashboardScreen()))};

    if (isOperator) {
      return [actions[0], actions[1], actions[2], monitoringAction, actions[3]];
    } else if (isTechnician) {
      return [actions[2], actions[1], monitoringAction, actions[0], actions[3]];
    } else if (isManager || isSuperManager) {
      final allAction = {'title': 'View All Jobs', 'icon': Icons.factory, 'color': const Color(0xFF64748B), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()))};
      return [actions[0], allAction, monitoringAction];
    } else {
      return [...actions, monitoringAction];
    }
  }

  double get _iconSize => _isDesktop ? 96 : 80;
  double get _cardPadding => _isDesktop ? 0 : 2 * 0.75;
  EdgeInsets get _cardPaddingInsets => _isDesktop ? const EdgeInsets.all(20) : const EdgeInsets.all(16);
  double get _gridSpacing => _isDesktop ? 6 : (_isTablet ? 15 : 12);
  double get _screenPadding => _isDesktop ? 20 : 16;

  @override
  void initState() {
    super.initState();
    _loadOnSiteStatus();
    _loadShowDeptOnly();
    _countSubscription = _firestoreService.getAllJobCards().listen((jobs) {
      final count = jobs.where((j) => !j.isCompleted && (currentEmployee == null || j.department == currentEmployee!.department || currentEmployee!.department == 'general')).length;
      if (mounted) setState(() => _openJobCount = count);
    });
    if (!kIsWeb) _setupFirebaseMessaging();
  }

  @override
  void dispose() {
    _countSubscription?.cancel();
    super.dispose();
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
        if (message.data['jobId'] != null) {
          setState(() => _pendingJobId = message.data['jobId']);
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data['notificationType'] == 'assigned') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAssignedJobsScreen()));
        } else if (message.data['jobId'] != null) {
          _handleJobDeepLink(message.data['jobId']);
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

  Future<void> _loadShowDeptOnly() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _showDeptOnly = prefs.getBool('showDeptOnly') ?? true);
    if (isSuperManager) {
      setState(() => _showDeptOnly = false);
    }
  }

  Future<void> _saveShowDeptOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showDeptOnly', value);
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
    String searchQuery = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Switch User'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Search employee...'),
                  onChanged: (value) => setDialogState(() => searchQuery = value.toLowerCase()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 300,
                  child: StreamBuilder<List<Employee>>(
                    stream: _firestoreService.getEmployeesStream(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const CircularProgressIndicator();
                      var employees = snapshot.data!;
                      if (searchQuery.isNotEmpty) {
                        employees = employees.where((e) => e.displayName.toLowerCase().contains(searchQuery)).toList();
                      }
                      employees.sort((a, b) => (a.isOnSite ? 0 : 1).compareTo(b.isOnSite ? 0 : 1));
                      return ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (context, index) {
                          final emp = employees[index];
                          return ListTile(
                            title: Text(emp.displayName),
                            subtitle: Text('${emp.department ?? ''} - ${emp.position ?? ''}'),
                            leading: Icon(
                              emp.isOnSite ? Icons.location_on : Icons.location_off,
                              color: emp.isOnSite ? Colors.green : Colors.red[400]!,
                              size: 20,
                            ),
                           tileColor: emp.isOnSite ? Colors.green.withValues(alpha: 26) : Colors.red.withValues(alpha: 26),
                            onTap: () async {
                              try {
                                await _firestoreService.saveLoggedInEmployee(emp.clockNo);

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
              ],
            ),
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
                      activeThumbColor: Colors.green,
                      inactiveTrackColor: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: _isDesktop ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: _gridSpacing,
            runSpacing: _gridSpacing,
            children: _quickActions.map((action) => _buildQuickActionCard(
              action['title'] as String,
              action['icon'] as IconData,
              action['color'] as Color,
              action['onTap'] as VoidCallback,
            )).toList(),
          ),

          const SizedBox(height: 24),

          // Recent Job Cards header with toggle directly next to title, whole block centered
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Recent Job Cards',
                  style: TextStyle(
                    fontSize: _isDesktop ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (isManager || isSuperManager) ...[
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Show Dept Only', style: TextStyle(color: Colors.white, fontSize: 14)),
                      Switch(
                        value: _showDeptOnly,
                        onChanged: (v) {
                          setState(() => _showDeptOnly = v);
                          _saveShowDeptOnly(v);
                        },
                        activeThumbColor: const Color(0xFFFF8C42),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildRecentJobCards(),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
    Widget card = Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: _cardPaddingInsets,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: _iconSize, color: color),
              SizedBox(height: _isDesktop ? 8 : 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
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

    if (title == 'View All Jobs') {
      card = Stack(
        children: [
          card,
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                _openJobCount.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }
    return card;
  }

  Widget _buildJobCardWidget(JobCard job) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'P${job.priority}',
                      style: TextStyle(
                        color: _getPriorityColor('P${job.priority}'),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: ' | ${job.department ?? 'N/A'} > ${job.area ?? 'N/A'} > ${job.machine ?? 'N/A'} > ${job.part ?? 'N/A'} | ${job.operator ?? 'Unknown'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (job.jobCardNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                               color: Colors.blue.withValues(alpha: 204),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'JC #${job.jobCardNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      job.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (job.comments.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _getLastCommentPreview(job.comments),
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade300, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (job.notes.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  job.notes.split('\n').first.trim(),
                  style: const TextStyle(fontSize: 13, color: Colors.white70, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                             color: _getStatusColor(job.status.name).withValues(alpha: 51),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.status.displayName,
                      style: TextStyle(
                        color: _getStatusColor(job.status.name),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                             color: Colors.blueGrey.withValues(alpha: 64),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.type.displayName,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    job.assignedNames?.join(', ') ?? 'Unassigned',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    job.lastUpdatedAt != null ? _formatDateTime(job.lastUpdatedAt!) : '—',
                    style: const TextStyle(color: Color(0xFFFF8C42), fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      if (job.comments.isNotEmpty) Icon(Icons.comment_outlined, size: 16, color: Colors.blue[400]),
                      if (job.notes.isNotEmpty) Icon(Icons.build_outlined, size: 16, color: Colors.orange[400]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentJobCards() {
    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('Error loading recent jobs: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final allJobs = snapshot.data!;
        if (allJobs.isEmpty) {
          return const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No recent jobs available', style: TextStyle(color: Colors.white70)),
              ),
            ),
          );
        }

        var recentJobs = allJobs
            .where((job) => job.lastUpdatedAt != null)
            .toList()
          ..sort((a, b) => (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0)));

        var topJobs = recentJobs.take(20).toList();

        if ((isManager || isSuperManager) && _showDeptOnly) {
          topJobs = topJobs.where((j) => j.department == currentEmployee!.department).toList();
        }

        return Column(
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topJobs.length,
              itemBuilder: (context, index) => _buildJobCardWidget(topJobs[index]),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen())),
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('View All Job Cards', style: TextStyle(fontSize: 15)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMyWorkTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Assigned'),
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
          itemBuilder: (context, index) => _buildJobCardWidget(assignedJobs[index]),
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
          itemBuilder: (context, index) => _buildJobCardWidget(completedJobs[index]),
        );
      },
    );
  }

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Colors.green[600]!;
      case 2: return Colors.lightGreen[500]!;
      case 3: return Colors.amber[600]!;
      case 4: return Colors.deepOrange[600]!;
      case 5: return const Color(0xFFFF3D00);
      default: return Colors.grey;
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

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getLastCommentPreview(String comments) {
    final parts = comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final lastComment = parts.last;
    final lines = lastComment.split('\n');
    return lines.length > 1 ? lines[1].trim() : lastComment.trim();
  }

  Widget _buildDashboardTab() {
    if (currentEmployee == null || !currentEmployee!.position.toLowerCase().contains('manager')) {
      return const Center(
        child: Text('Access denied. Manager role required.', style: TextStyle(color: Colors.white70)),
      );
    }
    return const ManagerDashboardScreen();
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

          if (currentEmployee?.name == 'G Peens') ...[
            Text(
              'Admin Settings',
              style: TextStyle(
                fontSize: _isDesktop ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: _isDesktop ? 20 : 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              icon: const Icon(Icons.settings),
              label: const Text('Manage Collections'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14B8A6),
                foregroundColor: Colors.white,
              ),
            ),
            SizedBox(height: _isDesktop ? 32 : 24),
          ],

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

  Widget _buildCopperTab() {
    return Center(
      child: ElevatedButton(
        onPressed: _showCopperAuthDialog,
        child: const Text('Access Copper Storage'),
      ),
    );
  }

  void _showCopperAuthDialog() {
    final clockController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Clock Number'),
        content: TextField(
          controller: clockController,
          decoration: const InputDecoration(labelText: 'Clock Card Number'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (['22', '5421', '20'].contains(clockController.text.trim())) {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CopperStorageScreen()));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Access denied. Only authorized clock cards allowed.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Access'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleJobDeepLink(String jobId) async {
    try {
      final job = await _firestoreService.getJobCard(jobId);
      if (job != null && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)));
      }
    } catch (e) {
      debugPrint('Error handling job deep link: $e');
    }
  }

  void _onItemTapped(int index) {
    if (index >= [
      _buildHomeTab(),
      _buildMyWorkTab(),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        _buildDashboardTab(),
      _buildSettingsTab(),
      if (_isCopperAuthorized)
        _buildCopperTab(),
    ].length) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingJobId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleJobDeepLink(_pendingJobId!);
        _pendingJobId = null;
      });
    }

    final List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.home),
        label: 'Home',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.assignment),
        label: 'My Work',
      ),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        const BottomNavigationBarItem(
          icon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: 'Settings',
      ),
      if (_isCopperAuthorized)
        const BottomNavigationBarItem(
          icon: Icon(Icons.inventory),
          label: 'Copper',
        ),
    ];

    final List<Widget> children = [
      _buildHomeTab(),
      _buildMyWorkTab(),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        _buildDashboardTab(),
      _buildSettingsTab(),
      if (_isCopperAuthorized)
        _buildCopperTab(),
    ];

    if (_selectedIndex >= children.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showPasswordDialog(context),
          child: const Text('CTP Job Cards'),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromRGBO(255, 140, 66, 1), Color.fromARGB(255, 124, 124, 124)],
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
        children: children,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: items,
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFFF8C42),
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1A1A1A),
        onTap: _onItemTapped,
      ),
    );
  }
}