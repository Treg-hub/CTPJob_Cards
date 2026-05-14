import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import '../models/employee.dart';
import '../models/job_card.dart';

import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show currentEmployee;
import '../widgets/skeleton_loader.dart';
import '../widgets/sync_indicator.dart';
import 'create_job_card_screen.dart';
import 'view_job_cards_screen.dart';
import 'my_assigned_jobs_screen.dart';
import 'manager_dashboard_screen.dart';
import 'job_card_detail_screen.dart';
import 'copper_dashboard_screen.dart';
import 'settings_screen.dart';
import 'daily_review_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();
  final LocationService _locationService = LocationService();

  bool isOnSite = true;
  bool _overrideOnSite = false;
  String? _pendingJobId;
  bool _showDeptOnly = true;
  int _openJobCount = 0;
  StreamSubscription<List<JobCard>>? _countSubscription;
  StreamSubscription<Employee>? _employeeSubscription;
  bool _testMode = false;
  Timer? _testModeTimer;
  int _pendingReviewCount = 0;
  StreamSubscription<List<JobCard>>? _reviewCountSubscription;


  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  bool get isManager => currentEmployee?.position.toLowerCase().contains('manager') ?? false;
  bool get isTechnician => (currentEmployee?.position.toLowerCase().contains('mechanical') ?? false) ||
                           (currentEmployee?.position.toLowerCase().contains('electrical') ?? false);
  bool get isOperator => !(isManager || isTechnician);
  bool get isSuperManager => currentEmployee?.department.toLowerCase() == 'general';

  bool get _isCopperAuthorized => ['22', '5421', '20'].contains(currentEmployee?.clockNo ?? '');

  List<Map<String, dynamic>> get _quickActions {
    final actions = [
      {'title': 'Create Job Card', 'icon': Icons.add_circle, 'color': const Color(0xFFFF8C42), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen()))},
      {'title': 'View Jobs', 'icon': Icons.list_alt, 'color': const Color(0xFF64748B), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()))},
      {'title': 'My Assigned Jobs', 'icon': Icons.assignment_turned_in, 'color': const Color(0xFF10B981), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAssignedJobsScreen()))},
    ];

    if (isOperator || !isManager && !isTechnician) {
      return [actions[0], actions[1], actions[2]];
    } else if (isTechnician) {
      return [actions[2], actions[1], actions[0]];
    } else if (isManager || isSuperManager) {
      final viewJobsAction = {'title': 'View Jobs', 'icon': Icons.factory, 'color': const Color(0xFF64748B), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()))};
      return [actions[0], viewJobsAction];
    } else {
      return actions;
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
    WidgetsBinding.instance.addObserver(this);
    _loadShowDeptOnly();
    _loadOverrideOnSite();
    _loadTestMode();

    if (currentEmployee != null) {
      _employeeSubscription = _firestoreService
          .getEmployeeStream(currentEmployee!.clockNo)
          .listen((emp) {
        if (mounted) {
          setState(() => isOnSite = emp.isOnSite);
        }
      });
    }

    if (!kIsWeb) {
      _notificationService.refreshToken();
    }

    try {
      _countSubscription = _firestoreService.getAllJobCards().listen((jobs) {
        final count = jobs.where((j) => !j.isClosed && 
          (currentEmployee == null || j.department == currentEmployee!.department || currentEmployee!.department == 'general')).length;
        if (mounted) setState(() => _openJobCount = count);
      });
    } catch (e) {
      debugPrint('Error setting up job count subscription: $e');
    }

    if (kIsWeb && isManager) {
      _reviewCountSubscription = _firestoreService.getAllJobCards().listen((jobs) {
        if (!mounted) return;
        final manager = currentEmployee;
        if (manager == null) return;
        final clockNo = manager.clockNo;
        final pos = manager.position.toLowerCase();
        final isElec = pos.contains('electrical') && pos.contains('manager');
        final isMech = pos.contains('mechanical') && pos.contains('manager');
        final count = jobs.where((c) {
          final inScope = isElec
              ? (c.type == JobType.electrical || c.type == JobType.mechanicalElectrical)
              : isMech
                  ? (c.type == JobType.mechanical || c.type == JobType.mechanicalElectrical)
                  : c.department == manager.department;
          return inScope && !c.reviewedBy.containsKey(clockNo);
        }).length;
        setState(() => _pendingReviewCount = count);
      });
    }

    if (!kIsWeb) _setupFirebaseMessaging();
  }

  @override
  void dispose() {
    _employeeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _countSubscription?.cancel();
    _reviewCountSubscription?.cancel();
    _testModeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_overrideOnSite && !_testMode) {
      _locationService.checkCurrentLocation();
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    try {
      await _notificationService.initialize();
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (!mounted) return;
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

  Future<void> _loadOverrideOnSite() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _overrideOnSite = prefs.getBool('overrideOnSite') ?? false);
  }

  Future<void> _loadTestMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _testMode = prefs.getBool('testMode') ?? false);
    if (_testMode) {
      _startTestModeTimer();
    }
  }

  Future<void> _saveTestMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('testMode', value);
  }

  void _startTestModeTimer() {
    _testModeTimer?.cancel();

    _testModeTimer = Timer(const Duration(hours: 2), () async {
      if (mounted && _testMode) {
        await _disableTestMode();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Test Mode automatically disabled after 2 hours'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });
  }

  Future<void> _disableTestMode() async {
    setState(() => _testMode = false);
    await _saveTestMode(false);
    _testModeTimer?.cancel();

    await _locationService.checkCurrentLocation();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test Mode disabled - Real geofence active'), backgroundColor: Colors.green),
      );
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter password'), backgroundColor: Colors.red));
                return;
              }
              try {
                final correctPassword = await _firestoreService.getSwitchUserPassword();
                if (password != correctPassword) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red));
                  }
                  return;
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  _showUserSwitchDialog(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
                            subtitle: Text('${emp.department} - ${emp.position}'),
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

  void _showFeedbackDialog() {
    final TextEditingController feedbackController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What improvements would you like to see?'),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Type your feedback here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42)),
            onPressed: () async {
              final feedback = feedbackController.text.trim();
              if (feedback.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter some feedback')),
                );
                return;
              }

              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await FirebaseFirestore.instance.collection('feedback').add({
                  'feedback': feedback,
                  'userName': currentEmployee?.name ?? 'Unknown',
                  'clockNo': currentEmployee?.clockNo ?? 'Unknown',
                  'timestamp': FieldValue.serverTimestamp(),
                });

                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Thank you! Your feedback has been submitted.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Error submitting feedback: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_screenPadding),
      child: Column(
        children: [
          SizedBox(
            height: 72,
            child: Card(
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
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: _isDesktop ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: _gridSpacing,
            runSpacing: _gridSpacing,
            children: [
              ..._quickActions.map((action) => _buildQuickActionCard(
                action['title'] as String,
                action['icon'] as IconData,
                action['color'] as Color,
                action['onTap'] as VoidCallback,
              )),
              if (kIsWeb && isManager)
                _DailyReviewTile(
                  pendingCount: _pendingReviewCount,
                  iconSize: _iconSize,
                  padding: _cardPaddingInsets,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DailyReviewScreen()),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          if (isManager || isSuperManager) ...[
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Recent Job Cards',
                    style: TextStyle(
                      fontSize: _isDesktop ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Show Dept Only', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
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
              ),
            ),
            const SizedBox(height: 12),
            _buildRecentJobCards(),
          ],
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    if (title == 'View Jobs') {
      card = Stack(
        children: [
          card,
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job))),
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
                      text: ' | ${job.department} > ${job.area} > ${job.machine} > ${job.part} | ${job.operator}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'JC #${job.jobCardNumber}',
                        style: TextStyle(color: onColor(Colors.blue), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      job.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.normal,
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
                  job.notes.split('\n').last.trim(),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
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
                      color: _getStatusColor(job.status.name),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.status.displayName,
                      style: TextStyle(color: onColor(_getStatusColor(job.status.name)), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.type.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          (job.assignedNames is List)
                              ? (job.assignedNames as List).join(', ')
                              : (job.assignedNames?.toString() ?? 'Unassigned'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          job.lastUpdatedAt != null ? _formatDateTime(job.lastUpdatedAt!) : '—',
                          style: const TextStyle(color: Color(0xFFFF8C42), fontSize: 12),
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
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
              child: Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    SkeletonLoader(height: 80),
                    SizedBox(height: 12),
                    SkeletonLoader(height: 80),
                    SizedBox(height: 12),
                    SkeletonLoader(height: 80),
                  ],
                ),
              ),
            ),
          );
        }

        final allJobs = snapshot.data!;
        if (allJobs.isEmpty) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No recent jobs available', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          );
        }

        var recentJobs = allJobs.where((job) => job.lastUpdatedAt != null).toList()
          ..sort((a, b) => (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0)));

        var topJobs = recentJobs.take(20).toList();

        if ((isManager || isSuperManager) && _showDeptOnly) {
          topJobs = topJobs.where((j) => j.department == currentEmployee!.department).toList();
        }

        if (kIsWeb && (isManager || isSuperManager)) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildFilteredRecentJobs(JobType.electrical)),
                  Expanded(child: _buildFilteredRecentJobs(JobType.mechanical)),
                ],
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
        } else {
          return AnimationLimiter(
            child: Column(
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: topJobs.length,
                  itemBuilder: (context, index) {
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 375),
                      child: SlideAnimation(
                        verticalOffset: 50.0,
                        child: FadeInAnimation(
                          child: _buildJobCardWidget(topJobs[index]),
                        ),
                      ),
                    );
                  },
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
            ),
          );
        }
      },
    );
  }

  Widget _buildFilteredRecentJobs(JobType type) {
    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    SkeletonLoader(height: 80),
                    SizedBox(height: 12),
                    SkeletonLoader(height: 80),
                    SizedBox(height: 12),
                    SkeletonLoader(height: 80),
                  ],
                ),
              ),
            ),
          );
        }

        final allJobs = snapshot.data!;
        if (allJobs.isEmpty) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No ${type.displayName} jobs available', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          );
        }

        var recentJobs = allJobs
            .where((job) => job.lastUpdatedAt != null && job.type == type)
            .toList()
          ..sort((a, b) => (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0)));

        var topJobs = recentJobs.take(10).toList();

        return AnimationLimiter(
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topJobs.length,
            itemBuilder: (context, index) {
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: _buildJobCardWidget(topJobs[index]),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMyWorkTab() {
    if (kIsWeb) {
      return Column(
        children: [
          Text(
            'Assigned | History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildAssignedJobs()),
                Expanded(child: _buildWorkHistory()),
              ],
            ),
          ),
        ],
      );
    } else {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Assigned'),
                Tab(text: 'History'),
              ],
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
  }

  Widget _buildAssignedJobs() {
    if (currentEmployee == null) {
      return Center(
        child: Text('Please log in to view assigned jobs', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAssignedJobCards(currentEmployee!.clockNo),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final assignedJobs = snapshot.data!;

        if (assignedJobs.isEmpty) {
          return Center(
            child: Text('No jobs assigned to you', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
      return Center(
        child: Text('Please log in to view work history', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allJobs = snapshot.data!;
        final assignedJobs = allJobs
            .where((job) => (job.status == JobStatus.monitor || job.status == JobStatus.closed) &&
                            (job.assignedClockNos?.contains(currentEmployee!.clockNo) ?? false))
            .toList()
          ..sort((a, b) {
            if (a.status == JobStatus.monitor && b.status != JobStatus.monitor) return -1;
            if (a.status != JobStatus.monitor && b.status == JobStatus.monitor) return 1;
            return (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0));
          });

        if (assignedJobs.isEmpty) {
          return Center(
            child: Text('No work history', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Theme.of(context).appColors.priority1;
      case 2: return Theme.of(context).appColors.priority2;
      case 3: return Theme.of(context).appColors.priority3;
      case 4: return Theme.of(context).appColors.priority4;
      case 5: return Theme.of(context).appColors.priority5;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Theme.of(context).appColors.statusOpen;
      case 'in progress':
        return Theme.of(context).appColors.statusInProgress;
      case 'completed':
        return Theme.of(context).appColors.statusCompleted;
      case 'cancelled':
        return Theme.of(context).appColors.statusCancelled;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getLastCommentPreview(String comments) {
    final parts = comments.split('\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final lastComment = parts.last;
    final lines = lastComment.split('');
    return lines.length > 1 ? lines[1].trim() : lastComment.trim();
  }

  Widget _buildDashboardTab() {
    if (currentEmployee == null || !currentEmployee!.position.toLowerCase().contains('manager')) {
      return Center(
        child: Text('Access denied. Manager role required.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return const ManagerDashboardScreen();
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
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CopperDashboardScreen()));
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

  void _onItemTapped(int index) {
    final List<Widget> children = [
      _buildHomeTab(),
      _buildMyWorkTab(),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        _buildDashboardTab(),
      if (_isCopperAuthorized)
        _buildCopperTab(),
    ];

    if (index >= children.length) return;

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
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      const BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'My Work'),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
      if (_isCopperAuthorized)
        const BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Copper'),
    ];

    final List<Widget> children = [
      _buildHomeTab(),
      _buildMyWorkTab(),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        _buildDashboardTab(),
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
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncIndicator(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: children,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: items,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
      floatingActionButton: Column(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    // TEST LOCATION BUTTON (Blue)
    FloatingActionButton(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        await _locationService.checkCurrentLocation();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('📍 Location check triggered'),
            backgroundColor: Colors.blue,
          ),
        );
      },
      backgroundColor: Colors.blue,
      tooltip: 'Test Location Check',
      child: const Icon(Icons.location_on, color: Colors.white),
    ),
    const SizedBox(height: 16),

    // Feedback button (original)
    FloatingActionButton(
      onPressed: _showFeedbackDialog,
      backgroundColor: const Color(0xFFFF8C42),
      tooltip: 'Give Feedback',
      child: const Icon(Icons.feedback, color: Colors.black),
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

}

// ---------------------------------------------------------------------------
// Daily Review tile with pulse animation when pending count exceeds 5
// ---------------------------------------------------------------------------

class _DailyReviewTile extends StatefulWidget {
  final int pendingCount;
  final VoidCallback onTap;
  final double iconSize;
  final EdgeInsets padding;

  const _DailyReviewTile({
    required this.pendingCount,
    required this.onTap,
    required this.iconSize,
    required this.padding,
  });

  @override
  State<_DailyReviewTile> createState() => _DailyReviewTileState();
}

class _DailyReviewTileState extends State<_DailyReviewTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;

  static const _threshold = 5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.035).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.pendingCount > _threshold) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_DailyReviewTile old) {
    super.didUpdateWidget(old);
    if (widget.pendingCount > _threshold && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (widget.pendingCount <= _threshold && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPulsing = widget.pendingCount > _threshold;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glowColor = isPulsing
            ? Color.lerp(Colors.orange, Colors.red, _glowAnim.value)!
            : Colors.transparent;

        return Transform.scale(
          scale: isPulsing ? _scaleAnim.value : 1.0,
          child: Stack(
            children: [
              Card(
                elevation: isPulsing ? 6 + _glowAnim.value * 6 : 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isPulsing
                      ? BorderSide(
                          color: glowColor.withValues(
                              alpha: 0.4 + _glowAnim.value * 0.6),
                          width: 2.0,
                        )
                      : BorderSide.none,
                ),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: widget.padding,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_late_outlined,
                          size: widget.iconSize,
                          color: isPulsing ? glowColor : const Color(0xFF5C6BC0),
                        ),
                        SizedBox(height: widget.iconSize <= 80 ? 12 : 8),
                        Text(
                          'Daily Review',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.pendingCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.pendingCount > _threshold
                          ? Colors.red
                          : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      widget.pendingCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
