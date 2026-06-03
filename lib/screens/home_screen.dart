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
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../services/location_service.dart';
import '../main.dart' show currentEmployee;
import '../utils/role.dart' as role_utils;
import '../widgets/job_card_tile.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/sync_indicator.dart';
import 'create_job_card_screen.dart';
import 'view_job_cards_screen.dart';
import 'manager_dashboard_screen.dart';
import 'job_card_detail_screen.dart';
import 'copper_dashboard_screen.dart';
import 'notification_inbox_screen.dart';
import 'settings_screen.dart';
import 'daily_review_screen.dart';
import 'waste_home_screen.dart';

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
  bool? _previousIsOnSite;
  bool _overrideOnSite = false;
  String? _pendingJobId;
  bool _showDeptOnly = true;
  int _openJobCount = 0;
  int _inProgressCount = 0;
  StreamSubscription<List<JobCard>>? _countSubscription;
  StreamSubscription<Employee>? _employeeSubscription;
  bool _testMode = false;
  Timer? _testModeTimer;
  int _pendingReviewCount = 0;
  StreamSubscription<List<JobCard>>? _reviewCountSubscription;

  String? _myWorkSelectedDepartment;
  String? _myWorkSelectedArea;
  String? _myWorkSelectedMachine;


  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  bool get isManager => role_utils.roleFromEmployee(currentEmployee) == role_utils.UserRole.manager;
  bool get isTechnician => role_utils.roleFromEmployee(currentEmployee) == role_utils.UserRole.technician;
  bool get isOperator => role_utils.roleFromEmployee(currentEmployee) == role_utils.UserRole.operator;
  bool get isSuperManager => role_utils.isSuperManager(currentEmployee);

  bool get _isCopperAuthorized => role_utils.isCopperAuthorized(currentEmployee);

  /// Returns true when the currently visible tab is the Waste tab.
  /// The Waste tab index is dynamic — it shifts depending on whether the
  /// Manager and Copper tabs are present for this user.
  bool get _isOnWasteTab {
    if (!role_utils.isWasteUser(currentEmployee) ||
        !role_utils.isWasteTrackEnabledSync()) {
      return false;
    }
    int idx = 2; // 0=Home, 1=MyWork
    if (currentEmployee != null &&
        currentEmployee!.position.toLowerCase().contains('manager')) {
      idx++;
    }
    if (_isCopperAuthorized) { idx++; }
    return _selectedIndex == idx;
  }

  void _setupEmployeeStream(String clockNo) {
    _employeeSubscription = _firestoreService
        .getEmployeeStream(clockNo)
        .listen((emp) {
      if (!mounted) return;
      final wasOffsite = _previousIsOnSite == false;
      final isNowOnsite = emp.isOnSite;
      setState(() {
        currentEmployee = emp;
        isOnSite = emp.isOnSite;
        _previousIsOnSite = emp.isOnSite;
      });
      if (wasOffsite && isNowOnsite) {
        _checkInboxOnReturn(clockNo);
      }
    });
  }

  void _checkInboxOnReturn(String clockNo) {
    FirebaseFirestore.instance
        .collection('notification_inbox')
        .doc(clockNo)
        .collection('items')
        .where('read', isEqualTo: false)
        .get()
        .then((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final count = snap.docs.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Welcome back! $count notification${count == 1 ? '' : 's'} waiting for review.'),
          action: SnackBarAction(
            label: 'Open',
            textColor: const Color(0xFFFF8C42),
            onPressed: () {
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationInboxScreen()),
                );
              }
            },
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }).catchError((e) {
      debugPrint('HomeScreen: inbox check on return failed: $e');
    });
  }

  Future<void> _tryLoadCurrentEmployee() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      // Phase 1: immediately show cached name while Firestore loads
      if (currentEmployee == null) {
        final name = prefs.getString('loggedInName') ?? '';
        final position = prefs.getString('loggedInPosition') ?? '';
        final department = prefs.getString('loggedInDepartment') ?? '';
        if (name.isNotEmpty && mounted) {
          setState(() {
            currentEmployee = Employee(
              clockNo: clockNo,
              name: name,
              position: position,
              department: department,
            );
          });
        }
      }

      // Phase 2: replace stub with canonical Firestore data
      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp != null && mounted) {
        setState(() => currentEmployee = emp);
        _setupEmployeeStream(clockNo);
      }
    } catch (e) {
      debugPrint('HomeScreen: deferred employee load failed: $e');
    }
  }

  bool get _canCreateJobCard => isOnSite || _overrideOnSite;

  /// Returns true if [job] falls within the current manager's scope.
  /// Mechanical managers → Mechanical + MechElec types only.
  /// Electrical managers → Electrical + MechElec types only.
  /// Super managers (department == "general") → all jobs.
  /// Other managers → jobs matching their department.
  bool _isInManagerScope(JobCard job) {
    final emp = currentEmployee;
    if (emp == null) return true;
    if (emp.department.toLowerCase() == 'general') return true;
    final pos = emp.position.toLowerCase();
    if (pos.contains('electrical') && pos.contains('manager')) {
      return job.type == JobType.electrical || job.type == JobType.mechanicalElectrical;
    }
    if (pos.contains('mechanical') && pos.contains('manager')) {
      return job.type == JobType.mechanical || job.type == JobType.mechanicalElectrical;
    }
    return job.department == emp.department;
  }

  List<Map<String, dynamic>> get _quickActions {
    final createAction = {'title': 'Create Job Card', 'icon': Icons.add_circle, 'color': const Color(0xFFFF8C42), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen()))};
    final viewJobsAction = {'title': 'View Jobs', 'icon': Icons.list_alt, 'color': const Color(0xFF64748B), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()))};

    List<Map<String, dynamic>> result;
    if (isManager || isSuperManager) {
      final viewJobsFactory = {'title': 'View Jobs', 'icon': Icons.factory, 'color': const Color(0xFF64748B), 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()))};
      result = [createAction, viewJobsFactory];
    } else {
      result = [createAction, viewJobsAction];
    }

    if (!_canCreateJobCard) {
      result = result.where((a) => a['title'] != 'Create Job Card').toList();
    }
    return result;
  }

  double get _iconSize => _isDesktop ? 96 : 80;
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
      _setupEmployeeStream(currentEmployee!.clockNo);
    } else {
      _tryLoadCurrentEmployee();
    }

    if (!kIsWeb) {
      _notificationService.refreshToken();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await UpdateService().checkForUpdate(context);
        } catch (e) {
          debugPrint('Update check error: $e');
        }
        try {
          await NotificationService().checkPendingJobNavigation();
        } catch (e) {
          debugPrint('Pending job navigation error: $e');
        }
      });
    }

    try {
      _countSubscription = _firestoreService.getAllJobCards().listen((jobs) {
        final filtered = jobs.where((j) => !j.isClosed && _isInManagerScope(j)).toList();
        if (mounted) {
          setState(() {
            _openJobCount = filtered.where((j) => j.status == JobStatus.open).length;
            _inProgressCount = filtered.where((j) => j.status == JobStatus.inProgress).length;
          });
        }
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
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (!mounted) return;
        if (message.data['notificationType'] == 'assigned') {
          setState(() => _selectedIndex = 1);
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
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: _isDesktop ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Wrap(
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
                if (kIsWeb && (isManager || isSuperManager))
                  _DailyReviewTile(
                    pendingCount: _pendingReviewCount,
                    iconSize: _iconSize,
                    padding: _cardPaddingInsets,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DailyReviewScreen()),
                    ),
                  ),
              ],
            ),
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
                (_openJobCount + _inProgressCount).toString(),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }
    return card;
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

        var recentJobs = allJobs
            .where((job) =>
                job.status == JobStatus.open || job.status == JobStatus.inProgress)
            .toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

        var topJobs = recentJobs.take(20).toList();

        if ((isManager || isSuperManager) && _showDeptOnly) {
          topJobs = topJobs.where(_isInManagerScope).toList();
        }

        if (kIsWeb && (isManager || isSuperManager)) {
          final openJobs = topJobs.where((j) => j.status == JobStatus.open).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          final inProgressJobs = topJobs.where((j) => j.status == JobStatus.inProgress).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildStatusColumn('Open', openJobs, const Color(0xFFFF8C42))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatusColumn('In Progress', inProgressJobs, Colors.blue)),
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
                          child: JobCardTile(
                            job: topJobs[index],
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: topJobs[index]))),
                          ),
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

  Widget _buildStatusColumn(String title, List<JobCard> jobs, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${jobs.length}',
                style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (jobs.isEmpty)
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No $title jobs',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: jobs.length,
            itemBuilder: (context, index) => JobCardTile(
              job: jobs[index],
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: jobs[index]))),
            ),
          ),
      ],
    );
  }

  Widget _buildMyWorkTab() {
    if (currentEmployee == null) {
      return Center(
        child: Text('Please log in to view your work',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getMyJobCards(currentEmployee!.clockNo),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data!;

        final activeJobs = all
            .where((j) => j.status == JobStatus.open || j.status == JobStatus.inProgress)
            .toList()
          ..sort((a, b) =>
              (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0)));

        final monitorJobs = all
            .where((j) => j.status == JobStatus.monitor)
            .toList()
          ..sort((a, b) =>
              (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0)));

        final closedJobs = all
            .where((j) => j.status == JobStatus.closed)
            .toList()
          ..sort((a, b) =>
              (b.lastUpdatedAt ?? DateTime(0)).compareTo(a.lastUpdatedAt ?? DateTime(0)));

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: 'Active (${activeJobs.length})'),
                  Tab(text: 'Monitoring (${monitorJobs.length})'),
                  Tab(text: 'Closed (${closedJobs.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildActiveTab(activeJobs),
                    _buildReadOnlyJobList(monitorJobs, 'No jobs in monitoring'),
                    _buildReadOnlyJobList(closedJobs, 'No closed jobs'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _operatorRestrictedFor(JobCard job) =>
      isOperator && job.type != JobType.maintenance;

  Future<void> _startWork(JobCard job) async {
    try {
      await _firestoreService.saveJobCardOfflineAware(
        job.copyWith(status: JobStatus.inProgress, startedAt: DateTime.now()),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Work started'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting work: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMyWorkCompleteDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    bool isCompleting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Complete Job'),
          content: TextField(
            controller: notesController,
            decoration: const InputDecoration(labelText: 'Description/Corrective Action Taken'),
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isCompleting
                  ? null
                  : () async {
                      final note = notesController.text.trim();
                      if (note.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a description'),
                              backgroundColor: Colors.red),
                        );
                        return;
                      }
                      setDialogState(() => isCompleting = true);
                      try {
                        final now = DateTime.now();
                        final user = currentEmployee?.name ?? 'User';
                        final timestamp =
                            '[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}]';
                        final completedJob = job.copyWith(
                          status: JobStatus.closed,
                          completedBy: user,
                          completedAt: now,
                          notes: job.notes.isNotEmpty
                              ? '${job.notes}\n\n$timestamp Completed by $user: $note'
                              : '$timestamp Completed by $user: $note',
                        );
                        await _firestoreService.saveJobCardOfflineAware(completedJob);

                        if (job.operatorClockNo != null) {
                          try {
                            final creatorEmp =
                                await _firestoreService.getEmployee(job.operatorClockNo!);
                            if (creatorEmp?.fcmToken != null) {
                              await _notificationService.sendCreatorNotification(
                                recipientToken: creatorEmp!.fcmToken!,
                                jobCardId: job.id!,
                                jobCardNumber: job.jobCardNumber ?? 0,
                                operator: currentEmployee?.name ?? 'Unknown',
                                creator: job.operator,
                                department: job.department,
                                area: job.area,
                                machine: job.machine,
                                part: job.part,
                                description: job.description,
                                notificationType: 'closed',
                                assigneeName: currentEmployee?.name ?? 'Unknown',
                              );
                            }
                          } catch (e) {
                            debugPrint('Error sending creator notification: $e');
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Job completed')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error completing job: $e'),
                                backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setDialogState(() => isCompleting = false);
                      }
                    },
              child: isCompleting
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Complete'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMyWorkMonitorDialog(BuildContext context, JobCard job) {
    final notesController = TextEditingController();
    bool isMonitoring = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Monitoring'),
          content: TextField(
            controller: notesController,
            decoration: const InputDecoration(labelText: 'Description/Corrective Action Taken'),
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isMonitoring
                  ? null
                  : () async {
                      final note = notesController.text.trim();
                      if (note.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a description'),
                              backgroundColor: Colors.red),
                        );
                        return;
                      }
                      setDialogState(() => isMonitoring = true);
                      try {
                        final now = DateTime.now();
                        final user = currentEmployee?.name ?? 'User';
                        final timestamp =
                            '[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}]';
                        final monitoredJob = job.copyWith(
                          status: JobStatus.monitor,
                          monitoringStartedAt: now,
                          notes: job.notes.isNotEmpty
                              ? '${job.notes}\n\n$timestamp Monitoring started by $user: $note'
                              : '$timestamp Monitoring started by $user: $note',
                        );
                        await _firestoreService.saveJobCardOfflineAware(monitoredJob);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Job moved to monitoring')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error starting monitoring: $e'),
                                backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setDialogState(() => isMonitoring = false);
                      }
                    },
              child: isMonitoring
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Start Monitoring'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab(List<JobCard> allActive) {
    final departments = allActive.map((j) => j.department).toSet().toList()..sort();
    final areas = _myWorkSelectedDepartment == null
        ? <String>[]
        : allActive
            .where((j) => j.department == _myWorkSelectedDepartment)
            .map((j) => j.area)
            .toSet()
            .toList()
          ..sort();
    final machines = _myWorkSelectedArea == null
        ? <String>[]
        : allActive
            .where((j) =>
                j.department == _myWorkSelectedDepartment &&
                j.area == _myWorkSelectedArea)
            .map((j) => j.machine)
            .toSet()
            .toList()
          ..sort();

    var jobs = allActive;
    if (_myWorkSelectedDepartment != null) {
      jobs = jobs.where((j) => j.department == _myWorkSelectedDepartment).toList();
    }
    if (_myWorkSelectedArea != null) {
      jobs = jobs.where((j) => j.area == _myWorkSelectedArea).toList();
    }
    if (_myWorkSelectedMachine != null) {
      jobs = jobs.where((j) => j.machine == _myWorkSelectedMachine).toList();
    }

    return Column(
      children: [
        _buildMyWorkFilterChips(departments, areas, machines),
        Expanded(
          child: jobs.isEmpty
              ? Center(
                  child: Text(
                    allActive.isEmpty
                        ? 'No active jobs assigned to you'
                        : 'No jobs match the selected filters',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JobCardTile(
                          job: job,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => JobCardDetailScreen(jobCard: job))),
                        ),
                        if (!_operatorRestrictedFor(job))
                          _buildMyWorkActionButtons(context, job),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMyWorkActionButtons(BuildContext context, JobCard job) {
    const btnPadding = EdgeInsets.symmetric(vertical: 8);
    if (job.startedAt == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
        child: ElevatedButton(
          onPressed: () => _startWork(job),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.black,
            padding: btnPadding,
          ),
          child: const Text('Start'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _showMyWorkCompleteDialog(context, job),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.black,
                padding: btnPadding,
              ),
              child: const Text('Complete'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _showMyWorkMonitorDialog(context, job),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                padding: btnPadding,
              ),
              child: const Text('Monitor'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyWorkFilterChips(
      List<String> depts, List<String> areas, List<String> machines) {
    final hasFilters = _myWorkSelectedDepartment != null ||
        _myWorkSelectedArea != null ||
        _myWorkSelectedMachine != null;

    if (depts.isEmpty && !hasFilters) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: depts
                      .map((dept) => FilterChip(
                            label: Text(dept, style: const TextStyle(fontSize: 12)),
                            selected: _myWorkSelectedDepartment == dept,
                            onSelected: (_) => setState(() {
                              _myWorkSelectedDepartment = dept;
                              _myWorkSelectedArea = null;
                              _myWorkSelectedMachine = null;
                            }),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            labelStyle: _myWorkSelectedDepartment == dept
                                ? const TextStyle(color: Color(0xFFFF8C42))
                                : TextStyle(
                                    color: Theme.of(context).appColors.chipUnselectedLabel),
                          ))
                      .toList(),
                ),
              ),
              if (hasFilters)
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, size: 20),
                  tooltip: 'Clear filters',
                  onPressed: () => setState(() {
                    _myWorkSelectedDepartment = null;
                    _myWorkSelectedArea = null;
                    _myWorkSelectedMachine = null;
                  }),
                ),
            ],
          ),
          if (_myWorkSelectedDepartment != null && areas.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: areas
                  .map((area) => FilterChip(
                        label: Text(area, style: const TextStyle(fontSize: 12)),
                        selected: _myWorkSelectedArea == area,
                        onSelected: (_) => setState(() {
                          _myWorkSelectedArea = area;
                          _myWorkSelectedMachine = null;
                        }),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        labelStyle: _myWorkSelectedArea == area
                            ? const TextStyle(color: Color(0xFFFF8C42))
                            : TextStyle(
                                color: Theme.of(context).appColors.chipUnselectedLabel),
                      ))
                  .toList(),
            ),
          ],
          if (_myWorkSelectedArea != null && machines.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: machines
                  .map((machine) => FilterChip(
                        label: Text(machine, style: const TextStyle(fontSize: 12)),
                        selected: _myWorkSelectedMachine == machine,
                        onSelected: (_) =>
                            setState(() => _myWorkSelectedMachine = machine),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        labelStyle: _myWorkSelectedMachine == machine
                            ? const TextStyle(color: Color(0xFFFF8C42))
                            : TextStyle(
                                color: Theme.of(context).appColors.chipUnselectedLabel),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadOnlyJobList(List<JobCard> jobs, String emptyMessage) {
    if (jobs.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: jobs.length,
      itemBuilder: (context, index) => JobCardTile(
        job: jobs[index],
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => JobCardDetailScreen(jobCard: jobs[index]))),
      ),
    );
  }

  Widget _buildDashboardTab() {
    if (currentEmployee == null ||
        role_utils.roleFromEmployee(currentEmployee) != role_utils.UserRole.manager) {
      return Center(
        child: Text('Access denied. Manager role required.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
      if (role_utils.isWasteUser(currentEmployee) && role_utils.isWasteTrackEnabledSync())
        _buildWasteTab(),
    ];

    if (index >= children.length) return;

    setState(() {
      _selectedIndex = index;
    });
  }

  // ---------------------------------------------------------------------------
  // WASTE TRACK placeholder tab (will become the dedicated home for Security roles)
  // ---------------------------------------------------------------------------
  Widget _buildWasteTab() {
    // Security roles land here directly (per approved plan)
    return const WasteHomeScreen();
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
      if (role_utils.isWasteUser(currentEmployee) && role_utils.isWasteTrackEnabledSync())
        const BottomNavigationBarItem(icon: Icon(Icons.delete_outline), label: 'Waste'),
    ];

    final List<Widget> children = [
      _buildHomeTab(),
      _buildMyWorkTab(),
      if (currentEmployee != null && currentEmployee!.position.toLowerCase().contains('manager'))
        _buildDashboardTab(),
      if (_isCopperAuthorized)
        _buildCopperTab(),
      if (role_utils.isWasteUser(currentEmployee) && role_utils.isWasteTrackEnabledSync())
        _buildWasteTab(),   // TODO: real focused Waste home for Security Manager/Guard
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFFF8C42), isOnSite ? Colors.green : Colors.red],
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
          if (currentEmployee != null)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notification_inbox')
                  .doc(currentEmployee!.clockNo)
                  .collection('items')
                  .where('read', isEqualTo: false)
                  .snapshots(),
              builder: (ctx, snap) {
                final count = snap.data?.docs.length ?? 0;
                return IconButton(
                  icon: Badge(
                    label: count > 0 ? Text('$count') : null,
                    isLabelVisible: count > 0,
                    child: const Icon(Icons.notifications_outlined, color: Colors.black),
                  ),
                  tooltip: 'Notification Inbox',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationInboxScreen()),
                  ),
                );
              },
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
      floatingActionButton: _isOnWasteTab
          ? null
          : FloatingActionButton(
              onPressed: _showFeedbackDialog,
              backgroundColor: const Color(0xFFFF8C42),
              tooltip: 'Give Feedback',
              child: const Icon(Icons.feedback, color: Colors.black),
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
