import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import '../constants/collections.dart';
import '../models/employee.dart';
import '../models/job_card.dart';

import '../services/auth_claims_service.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../services/job_card_actions_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/whats_new_service.dart';
import '../theme/app_theme.dart';
import '../services/client_platform_service.dart';
import '../services/device_health_service.dart';
import '../services/location_service.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../providers/current_employee_provider.dart';
import '../providers/persona_provider.dart';
import '../utils/persona_audit.dart';
import '../utils/registry_admin.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/persona_banner.dart';
import '../widgets/persona_picker_dialog.dart';
import '../widgets/job_card_tile.dart';
import '../widgets/session_health_banner.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/geofence_health_banner.dart';
import '../widgets/update_available_banner.dart';
import 'create_job_card_screen.dart';
import 'view_job_cards_screen.dart';
import 'job_card_detail_screen.dart';
import 'my_feedback_screen.dart';
import 'feedback_admin_screen.dart';
import 'copper_dashboard_screen.dart';
import 'notification_inbox_screen.dart';
import 'settings_screen.dart';
import 'daily_review_screen.dart';
import 'job_card_history_screen.dart';
import 'work_report_hub_screen.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import 'waste_home_screen.dart';
import 'fleet_home_screen.dart';
import 'fleet_reporter_home_screen.dart';
import 'fleet_report_wizard_screen.dart';
import 'ink_home_screen.dart';
import 'ink_daily_readings_screen.dart';
import 'security_home_screen.dart';

import '../models/fleet_settings.dart';
import '../models/security_settings.dart';
import '../models/waste_settings.dart';
import '../providers/ink_provider.dart';
import '../providers/inbox_provider.dart';
import '../widgets/ink_daily_readings_banner.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../services/security_service.dart';
import '../services/waste_service.dart';
import '../utils/fleet_labels.dart';
import '../utils/list_load_state.dart';
import '../utils/presence_gating.dart';
import '../utils/screen_insets.dart';

enum _ShellTab { home, myWork, copper, waste, fleet, security }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final FirestoreService _firestoreService = FirestoreService();
  final JobCardActionsService _actions = JobCardActionsService();
  final NotificationService _notificationService = NotificationService();
  final LocationService _locationService = LocationService();

  bool isOnSite = true;
  bool? _previousIsOnSite;
  String? _pendingJobId;
  bool _showDeptOnly = true;
  int _openJobCount = 0;
  int _inProgressCount = 0;
  StreamSubscription<JobCardListSnapshot>? _countSubscription;
  StreamSubscription<List<JobCard>>? _inProgressSub;
  StreamSubscription<Employee>? _employeeSubscription;

  // Streams are created ONCE and held in state: a stream built inline in a
  // build method re-subscribes a fresh Firestore listener on every rebuild,
  // and any retry/backoff state in the resilient wrapper would reset with it.
  // The active (open+inProgress) snapshot is shared by the counts AND the
  // recent-jobs list — one Firestore listener instead of two for one query.
  JobCardListSnapshot? _activeJobsSnap;
  String? _myWorkClockNo;
  Stream<JobCardListSnapshot>? _myWorkStream;

  StreamSubscription<List<ConnectivityResult>>? _moduleSettingsConnSub;
  bool _testMode = false;
  Timer? _testModeTimer;
  // Debounces on/off-site snackbars so GPS jitter at the fence boundary can't
  // spam them — the notice only fires once the new state has held briefly.
  Timer? _presenceNoticeDebounce;
  int _pendingReviewCount = 0;
  StreamSubscription<List<JobCard>>? _reviewCountSubscription;
  StreamSubscription<RemoteMessage>? _messagingSubscription;

  String? _myWorkSelectedDepartment;
  String? _myWorkSelectedArea;
  String? _myWorkSelectedMachine;

  // Fleet Maintenance — cached settings loaded once in initState
  FleetSettings? _cachedFleetSettings;
  bool _fleetChecklistEnabled = false;

  // Waste Track — cached settings loaded once in initState
  WasteSettings? _cachedWasteSettings;

  // Site Security — cached settings loaded once in initState
  SecuritySettings? _cachedSecuritySettings;

  /// When true, first-frame update check ran without employee clock/dept —
  /// re-run channel match once the profile loads (targeted force/soft).
  bool _pendingCohortUpdateRecheck = false;

  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  bool get isManager => role_utils.roleFromEmployee(currentEmployee) == role_utils.UserRole.manager;
  bool get isTechnician => role_utils.roleFromEmployee(currentEmployee) == role_utils.UserRole.technician;
  bool get isOperator => role_utils.roleFromEmployee(currentEmployee) == role_utils.UserRole.operator;
  bool get isSuperManager => role_utils.isSuperManager(currentEmployee);

  bool get _isCopperAuthorized => role_utils.isCopperAuthorized(currentEmployee);

  bool get _canUseOnSiteModules => PresenceGating.canUseOnSiteOnlyModules(
        emp: currentEmployee,
        isOnSite: isOnSite,
      );

  bool get _isFleetUser => PresenceGating.showFleetTab(
        emp: currentEmployee,
        settings: _cachedFleetSettings,
        isOnSite: isOnSite,
      );

  bool get _canReportFleetIssue =>
      PresenceGating.canUseReporterFleetActions(
        emp: currentEmployee,
        settings: _cachedFleetSettings,
        isOnSite: isOnSite,
      );

  bool get _canDoFleetDailyCheck =>
      _fleetChecklistEnabled &&
      PresenceGating.canDoFleetDailyCheckOffSiteAware(
        emp: currentEmployee,
        settings: _cachedFleetSettings,
        isOnSite: isOnSite,
      );

  bool get _isSecurityRoleUser =>
      role_utils.canUseSecurityModule(
        currentEmployee,
        _cachedSecuritySettings,
      );

  bool get _showSecurityModule =>
      _isSecurityRoleUser && _canUseOnSiteModules;

  bool get _showWasteModule =>
      role_utils.isWasteUser(currentEmployee, _cachedWasteSettings) &&
      (_cachedWasteSettings?.wasteEnabled ?? true) &&
      _canUseOnSiteModules;

  /// Guards (not site security managers) — waste + gate are primary; hide job-card home UX.
  bool get _isSiteSecurityGuardOnly =>
      role_utils.isSiteSecurityGuardOnly(
        currentEmployee,
        _cachedSecuritySettings,
      );

  bool get _showMyWorkNav => !_isSiteSecurityGuardOnly;

  bool _fleetMechanicNavDone = false;
  bool _securityGuardNavDone = false;

  /// Index of the first module tab after Home / My Work / Copper.
  /// Must stay aligned with [_shellTabAtIndex] and the bottom-nav children list
  /// (Manager Dashboard tab was removed — do not reserve a slot for it).
  int _indexAfterCoreTabs() {
    var idx = 1; // 0 = Home
    if (_showMyWorkNav) idx++;
    if (_isCopperAuthorized) idx++;
    return idx;
  }

  int _copperTabIndex() {
    if (!_isCopperAuthorized) return -1;
    var idx = 1; // after Home
    if (_showMyWorkNav) idx++;
    return idx;
  }

  bool get _isOnCopperTab {
    final idx = _copperTabIndex();
    return idx >= 0 && _selectedIndex == idx;
  }

  int _wasteTabIndex() {
    if (!_showWasteModule) return -1;
    return _indexAfterCoreTabs();
  }

  /// Returns true when the currently visible tab is the Waste tab.
  bool get _isOnWasteTab {
    final idx = _wasteTabIndex();
    return idx >= 0 && _selectedIndex == idx;
  }

  int _fleetTabIndex() {
    if (!_isFleetUser) return -1;
    var idx = _indexAfterCoreTabs();
    if (_wasteTabIndex() >= 0) idx++;
    return idx;
  }

  int _securityTabIndex() {
    if (!_showSecurityModule) return -1;
    var idx = _indexAfterCoreTabs();
    if (_wasteTabIndex() >= 0) idx++;
    if (_fleetTabIndex() >= 0) idx++;
    return idx;
  }

  /// Returns true when the currently visible tab is the Fleet tab.
  bool get _isOnFleetTab {
    final idx = _fleetTabIndex();
    return idx >= 0 && _selectedIndex == idx;
  }

  /// Returns true when the currently visible tab is the Security tab.
  bool get _isOnSecurityTab {
    final idx = _securityTabIndex();
    return idx >= 0 && _selectedIndex == idx;
  }

  void _maybeOpenFleetTabForMechanic() {
    if (_fleetMechanicNavDone || !mounted || _pendingJobId != null) return;
    final settings = _cachedFleetSettings;
    if (settings == null || !settings.fleetEnabled) return;
    if (!role_utils.isFleetMechanic(currentEmployee, settings)) return;
    final idx = _fleetTabIndex();
    if (idx < 0) return;
    _fleetMechanicNavDone = true;
    _setShellTab(idx);
  }

  void _openFleetMachinesTab() {
    final settings = _cachedFleetSettings;
    final emp = currentEmployee;
    if (settings == null || emp == null) return;

    if (!PresenceGating.canUseReporterFleetActions(
      emp: emp,
      settings: settings,
      isOnSite: isOnSite,
    )) {
      PresenceGating.showOffSiteSnackBar(
        context,
        PresenceGating.offSiteReporterFleetMessage,
      );
      return;
    }

    // Dual-role users see the mechanic shell on the Fleet tab — open Machines in a
    // standalone reporter screen so daily-check / machine pickers stay consistent.
    if (role_utils.isFleetReporter(emp, settings) &&
        role_utils.isFleetMechanic(emp, settings)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const FleetReporterHomeScreen(
            initialTab: 0,
            standalone: true,
          ),
        ),
      );
      return;
    }

    ref.read(fleetReporterShellTabProvider.notifier).state = 0;
    final idx = _fleetTabIndex();
    if (idx >= 0) _setShellTab(idx);
  }

  void _maybeOpenModuleTabForSecurityGuard() {
    if (_securityGuardNavDone || !mounted || _pendingJobId != null) return;
    if (!_isSiteSecurityGuardOnly) return;

    final securityIdx = _securityTabIndex();
    if (securityIdx >= 0) {
      _securityGuardNavDone = true;
      _setShellTab(securityIdx);
      return;
    }

    final wasteIdx = _wasteTabIndex();
    if (wasteIdx >= 0) {
      _securityGuardNavDone = true;
      _setShellTab(wasteIdx);
    }
  }

  String get _appBarTitle {
    if (_isOnCopperTab) return 'Copper';
    if (_isOnWasteTab) return 'Waste Recovery';
    if (_isOnFleetTab) return 'Fleet Maintenance';
    if (_isOnSecurityTab) return 'Site Security';
    if (_isSiteSecurityGuardOnly && _selectedIndex == 0) {
      return 'Waste & Security';
    }
    return 'CTP Job Cards';
  }

  int? _lastClaimsVersion;

  void _setupEmployeeStream(String clockNo) {
    // Cancel any existing subscription first — reassigning without cancelling
    // leaks the old listener, which would fire the presence snackbars again
    // per orphaned stream. Also drop any pending presence notice so a debounce
    // armed for the previous user/clockNo can't fire after a switch.
    _employeeSubscription?.cancel();
    _presenceNoticeDebounce?.cancel();
    _employeeSubscription = _firestoreService
        .getEmployeeStream(clockNo)
        .listen((emp) {
      if (!mounted) return;
      final prevIsOnSite = _previousIsOnSite;
      final isNowOnsite = emp.isOnSite;
      setState(() {
        realEmployee = emp;
        isOnSite = emp.isOnSite;
        _previousIsOnSite = emp.isOnSite;
      });
      _resetTabIfHiddenModule();
      ref.invalidate(currentEmployeeProvider);
      // React only to a genuine change, and debounce it: GPS jitter at the
      // fence boundary flips isOnSite back and forth, which previously fired a
      // snackbar on every flip. Wait for the new state to settle, and if it
      // oscillated back in the meantime, fire nothing.
      if (prevIsOnSite != null && prevIsOnSite != isNowOnsite) {
        _presenceNoticeDebounce?.cancel();
        _presenceNoticeDebounce = Timer(const Duration(seconds: 45), () {
          if (!mounted || isOnSite != isNowOnsite) return;
          if (isNowOnsite) {
            _checkInboxOnReturn(clockNo);
          } else {
            _showOffSiteNotice();
          }
        });
      }
      // Claims plumbing (Phase 3 readiness): the server bumps claimsVersion
      // after minting custom auth claims; refresh the ID token so rules see
      // them without requiring a re-login.
      if (emp.claimsVersion != null && emp.claimsVersion != _lastClaimsVersion) {
        _lastClaimsVersion = emp.claimsVersion;
        FirebaseAuth.instance.currentUser
            ?.getIdToken(true)
            .then((_) => debugPrint('🔑 ID token refreshed (claimsVersion ${emp.claimsVersion})'))
            .catchError((Object e) => debugPrint('ID token refresh failed: $e'));
      }
    }, onError: (e) {
      if (e is StateError &&
          e.message == FirestoreService.employeeNotFoundOnServer) {
        // Server-confirmed deletion of the employee doc (never a cold-cache
        // miss — getEmployeeStream filters those). Surfaced via the session
        // banner; prefs and the offline queue are deliberately left intact.
        debugPrint('HomeScreen: employee doc deleted (server-confirmed)');
        SessionHealthBanner.flagAccountMissing();
        return;
      }
      debugPrint('HomeScreen: employee stream error: $e');
    });
  }



  void _checkInboxOnReturn(String clockNo) {
    FirebaseFirestore.instance
        .collection(Collections.notificationInbox)
        .doc(clockNo)
        .collection(Collections.notificationInboxItems)
        .where('read', isEqualTo: false)
        .get()
        .then((snap) {
      if (!mounted) return;
      final count = snap.docs.length;
      final message = count > 0
          ? 'You\'re on-site — $count message${count == 1 ? '' : 's'} waiting for you.'
          : 'You\'re on-site — no pending messages.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: count > 0
              ? SnackBarAction(
                  label: 'Open',
                  textColor: kBrandOrange,
                  onPressed: () {
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationInboxScreen()),
                      );
                    }
                  },
                )
              : null,
          duration: const Duration(seconds: 6),
        ),
      );
    }).catchError((e) {
      debugPrint('HomeScreen: inbox check on return failed: $e');
    });
  }

  void _showOffSiteNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'You\'ve left site — incoming alerts will be held until you return.'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _tryLoadCurrentEmployee() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      // Immediately show cached employee while Firestore loads
      if (realEmployee == null) {
        final name = prefs.getString('loggedInName') ?? '';
        final position = prefs.getString('loggedInPosition') ?? '';
        final department = prefs.getString('loggedInDepartment') ?? '';
        final adminFlag = prefs.getBool('loggedInAdmin') ?? false;
        if (name.isNotEmpty && mounted) {
          setState(() {
            realEmployee = Employee(
              clockNo: clockNo,
              name: name,
              position: position,
              department: department,
              isAdmin: adminFlag,
            );
          });
          ref.invalidate(currentEmployeeProvider);
          // If first-frame update check already ran without us, re-match channels.
          _maybeRecheckUpdateForCohort();
        }
      }

      // Start the real-time stream unconditionally so updates work even if
      // the one-shot fetch below fails (network down, Firestore warming up).
      _setupEmployeeStream(clockNo);

      // Phase 2: replace stub with canonical Firestore data
      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp != null && mounted) {
        _applyEmployeePresence(emp);
      } else if (realEmployee != null && mounted) {
        // Stub already applied above — still re-run channel match if pending.
        _maybeRecheckUpdateForCohort();
      }
    } catch (e) {
      debugPrint('HomeScreen: deferred employee load failed: $e');
    }
  }

  bool get _canCreateJobCard => PresenceGating.canCreateJobCard(
        emp: currentEmployee,
        isOnSite: isOnSite,
      );

  /// When presence flips off-site, the selected tab may no longer exist or
  /// another tab may slide into the same index (e.g. Waste hides → Fleet takes
  /// that slot). Reset to Home when the tab *type* at the current index changes.
  void _resetTabIfHiddenModule() {
    if (!mounted) return;
    final currentTab = _shellTabAtIndex(_selectedIndex);
    if (currentTab == null || !_isShellTabVisible(currentTab)) {
      _setShellTab(0);
    }
  }

  bool _isShellTabVisible(_ShellTab tab) => switch (tab) {
        _ShellTab.home => true,
        _ShellTab.myWork => _showMyWorkNav,
        _ShellTab.copper => _isCopperAuthorized,
        _ShellTab.waste => _showWasteModule,
        _ShellTab.fleet => _isFleetUser,
        _ShellTab.security => _showSecurityModule,
      };

  /// Live open-job counts / Recent Job Cards only for managers (read discipline).
  bool get _needsActiveJobsListener => isManager || isSuperManager;

  _ShellTab? _shellTabAtIndex(int index) {
    var i = 0;
    if (index == i++) return _ShellTab.home;
    if (_showMyWorkNav) {
      if (index == i++) return _ShellTab.myWork;
    }
    if (_isCopperAuthorized) {
      if (index == i++) return _ShellTab.copper;
    }
    if (_showWasteModule) {
      if (index == i++) return _ShellTab.waste;
    }
    if (_isFleetUser) {
      if (index == i++) return _ShellTab.fleet;
    }
    if (_showSecurityModule) {
      if (index == i++) return _ShellTab.security;
    }
    return null;
  }

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
      return job.type == JobType.mechanical ||
             job.type == JobType.mechanicalElectrical ||
             job.type == JobType.building ||
             job.type == JobType.specialist;
    }
    return job.department == emp.department;
  }

  // Quick Actions tile colours are grouped by function so linked tiles read
  // as a set: job-card actions share the brand orange, ink shares cyan,
  // fleet shares slate, and Daily Review is gold.
  static const Color _jobCardsGroup = kBrandOrange;
  static const Color _inkGroup = kInkModule;
  static const Color _fleetGroup = Color(0xFF64748B); // slate
  // Daily Review (gold/amber) is the separate _DailyReviewTile widget, which
  // carries its own amber constant so its pulse animation can override it.

  List<Map<String, dynamic>> _quickActions(WorkReportSettings? workReportSettings) {
    final createAction = {'title': 'Create Job Card', 'icon': Icons.add_circle, 'color': _jobCardsGroup, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateJobCardScreen()))};
    final historyAction = {'title': 'Job History', 'icon': Icons.history, 'color': _jobCardsGroup, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobCardHistoryScreen()))};

    List<Map<String, dynamic>> result;
    if (isManager || isSuperManager) {
      final viewJobsFactory = {
        'title': 'View Jobs',
        'icon': Icons.factory,
        'color': _jobCardsGroup,
        'badgeCount': _openJobCount + _inProgressCount,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()),
            ),
      };
      result = [createAction, viewJobsFactory, historyAction];
    } else {
      // Operators: no live open-count badge (avoids factory-wide active-jobs listener).
      final viewJobsAction = {
        'title': 'View Jobs',
        'icon': Icons.list_alt,
        'color': _jobCardsGroup,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ViewJobCardsScreen()),
            ),
      };
      result = [createAction, viewJobsAction, historyAction];
    }

    if (!_canCreateJobCard) {
      createAction['disabledReason'] = PresenceGating.offSiteCreateJobMessage;
    }
    if (_canReportFleetIssue) {
      result = [
        ...result,
        {
          'title': FleetLabels.reportProblem,
          'icon': Icons.forklift,
          'color': _fleetGroup,
          'onTap': () => openFleetReportWizard(context, forceStep1: true),
        },
      ];
    }
    if (_canDoFleetDailyCheck) {
      result = [
        ...result,
        {
          // Home tile uses the shorter "Daily Check" label.
          'title': 'Daily Check',
          'icon': Icons.fact_check_outlined,
          'color': _fleetGroup,
          'onTap': _openFleetMachinesTab,
        },
      ];
    }
    if (_canUseOnSiteModules && role_utils.isInkUser(currentEmployee)) {
      final inkEnabled =
          ref.watch(inkSettingsProvider).valueOrNull?.inkEnabled ?? true;
      if (inkEnabled) {
        result = [
          ...result,
          {
            'title': 'Ink Factory',
            'icon': Icons.water_drop,
            'color': _inkGroup,
            'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InkHomeScreen()),
                ),
          },
        ];
      }
    }
    if (_canUseOnSiteModules && role_utils.isInkMeterUser(currentEmployee)) {
      result = [
        ...result,
        {
          'title': 'Daily Readings',
          'icon': Icons.speed,
          'color': _inkGroup,
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InkDailyReadingsScreen()),
              ),
        },
      ];
    }
    if (role_utils.canUseWorkReportModule(
        currentEmployee, workReportSettings)) {
      result = [
        ...result,
        {
          'title': 'My Timesheet',
          'icon': Icons.schedule,
          'color': const Color(0xFF0D9488),
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WorkReportHubScreen()),
              ),
        },
      ];
    }
    // Admin feedback triage — kept on Home so it stays one tap away after
    // Factory Admin Overview regrouping (no longer under Admin Settings dump).
    if (role_utils.isAdmin(currentEmployee)) {
      result = [
        ...result,
        {
          'title': 'Feedback',
          'icon': Icons.feedback_outlined,
          'color': const Color(0xFF7C3AED),
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FeedbackAdminScreen()),
              ),
        },
      ];
    }
    // Vehicle at Gate / On-Foot Visitor are reached from the Security tab, not
    // the Home quick actions. Scan Tester lives under Factory Admin → Tools.
    return result;
  }

  double get _iconSize => _isDesktop ? 40 : (_isTablet ? 42 : 40);
  EdgeInsets get _cardPaddingInsets => EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _isDesktop || _isTablet ? 8 : 10,
      );
  double get _gridSpacing => _isDesktop ? 14 : (_isTablet ? 12 : 10);
  double get _screenPadding => _isDesktop ? 20 : 16;
  int get _gridColumns => _isDesktop ? 6 : (_isTablet ? 4 : 3);

  // Fixed tile height so Quick Actions can span the full width without the
  // tiles ballooning vertically — they stretch across, but never grow tall.
  // Desktop/tablet need a few extra px — icon + label + vertical padding was
  // overflowing by 1px on wide layouts with the old 104/112 extents.
  double get _gridTileHeight => _isDesktop ? 108 : (_isTablet ? 110 : 116);

  // Success flags for the one-shot module-settings loads. A load that
  // returned defaults for a missing doc still counts as success (the server
  // answered); only the catch path leaves a flag false so
  // _retryFailedModuleSettings never re-reads settings that loaded fine.
  bool _fleetSettingsLoaded = false;
  bool _wasteSettingsLoaded = false;
  bool _securitySettingsLoaded = false;

  Future<void> _loadFleetSettings({bool preferServer = false}) async {
    try {
      final service = FleetService();
      FleetSettings settings;
      if (preferServer) {
        try {
          settings =
              await service.getSettings(source: Source.server);
        } catch (_) {
          settings = await service.getSettings();
        }
      } else {
        settings = await service.getSettings();
      }
      final checklist = await service.getDailyChecklistConfig();
      if (mounted) {
        setState(() {
          _cachedFleetSettings = settings;
          _fleetChecklistEnabled = checklist.enabled;
        });
        _fleetSettingsLoaded = true;
        _maybeOpenFleetTabForMechanic();
      }
    } catch (e) {
      debugPrint('Fleet settings load error: $e');
    }
  }

  Future<void> _loadWasteSettings({bool preferServer = false}) async {
    try {
      WasteSettings settings;
      if (preferServer) {
        try {
          settings = await WasteService()
              .getWasteSettings(source: Source.server);
        } catch (_) {
          settings = await WasteService().getWasteSettings();
        }
      } else {
        settings = await WasteService().getWasteSettings();
      }
      if (mounted) {
        setState(() => _cachedWasteSettings = settings);
        _wasteSettingsLoaded = true;
        _maybeOpenModuleTabForSecurityGuard();
      }
    } catch (e) {
      debugPrint('Waste settings load error: $e');
    }
  }

  Future<void> _loadSecuritySettings({bool preferServer = false}) async {
    try {
      SecuritySettings settings;
      if (preferServer) {
        try {
          settings = await SecurityService()
              .getSettings(source: Source.server);
        } catch (_) {
          settings = await SecurityService().getSettings();
        }
      } else {
        settings = await SecurityService().getSettings();
      }
      if (mounted) {
        setState(() => _cachedSecuritySettings = settings);
        _securitySettingsLoaded = true;
        _maybeOpenModuleTabForSecurityGuard();
      }
    } catch (e) {
      debugPrint('Security settings load error: $e');
    }
  }

  /// Re-runs only the module-settings loads whose FIRST attempt failed
  /// (offline cold start). Without this, a mechanic's Fleet tab or a guard's
  /// Waste/Security hub stayed missing for the whole session. Fired on
  /// connectivity restore and app resume; zero extra reads when the initial
  /// loads succeeded.
  void _retryFailedModuleSettings() {
    if (!_fleetSettingsLoaded) _loadFleetSettings();
    if (!_wasteSettingsLoaded) _loadWasteSettings();
    if (!_securitySettingsLoaded) _loadSecuritySettings();
  }

  void _applyEmployeePresence(Employee emp) {
    setState(() {
      realEmployee = emp;
      isOnSite = emp.isOnSite;
      _previousIsOnSite ??= emp.isOnSite;
    });
    _resetTabIfHiddenModule();
    ref.invalidate(currentEmployeeProvider);
    _maybeRecheckUpdateForCohort();
  }

  /// Re-resolve update channels after a deferred employee load so Ink/testers
  /// force is not missed when the first Home check had no clock/dept.
  void _maybeRecheckUpdateForCohort() {
    if (kIsWeb || !_pendingCohortUpdateRecheck) return;
    if (realEmployee == null && currentEmployee == null) return;
    _pendingCohortUpdateRecheck = false;
    if (!mounted) return;
    unawaited(UpdateService().checkForUpdateIgnoringCooldown(context));
  }

  void _setupActiveJobsSubscription() {
    _countSubscription?.cancel();
    _countSubscription = null;
    // Managers / super only — operators use My Work + View Jobs without a
    // factory-wide open-jobs listener (Firestore Phase A).
    if (!_needsActiveJobsListener) {
      if (mounted &&
          (_activeJobsSnap != null ||
              _openJobCount != 0 ||
              _inProgressCount != 0)) {
        setState(() {
          _activeJobsSnap = null;
          _openJobCount = 0;
          _inProgressCount = 0;
        });
      }
      return;
    }
    _countSubscription =
        _firestoreService.getActiveJobCardsWithMeta().listen((snap) {
      if (!mounted) return;
      final filtered = snap.cards.where(_isInManagerScope).toList();
      setState(() {
        _activeJobsSnap = snap;
        _openJobCount =
            filtered.where((j) => j.status == JobStatus.open).length;
        _inProgressCount = filtered
            .where((j) => j.status == JobStatus.inProgress)
            .length;
      });
    }, onError: (e) {
      debugPrint('HomeScreen: active jobs stream error: $e');
    });
  }

  void _rearmActiveJobsStreamIfStuck() {
    if (!_needsActiveJobsListener) return;
    final snap = _activeJobsSnap;
    if (!shouldRearmActiveJobsOnResume(
      hasSnapshot: snap != null,
      isEmpty: snap?.cards.isEmpty ?? true,
      isFromCache: snap?.isFromCache ?? true,
    )) {
      return;
    }
    debugPrint('HomeScreen: re-arming active jobs stream on resume');
    _setupActiveJobsSubscription();
  }

  Future<void> _refreshEmployeeOnResume() async {
    final clockNo = realEmployee?.clockNo ??
        (await SharedPreferences.getInstance())
            .getString('loggedInClockNo');
    if (clockNo == null) return;

    final emp = await _firestoreService.getEmployee(clockNo);
    if (emp != null && mounted) {
      _applyEmployeePresence(emp);
    }
  }

  /// Warm resume after geofence / notification tap can leave Home in a stale
  /// off-site or partially-hydrated state until a cold restart. Mirror the
  /// cold-start path: refresh claims, presence, module settings, and re-arm
  /// job streams that are still showing cache-only skeletons.
  Future<void> _onAppResumed() async {
    unawaited(AuthClaimsService.refreshClaims());

    await _refreshEmployeeOnResume();

    if (!_testMode) {
      final onSite = await _locationService.checkCurrentLocation();
      if (onSite != null && mounted) {
        setState(() {
          isOnSite = onSite;
          if (realEmployee != null) {
            realEmployee = realEmployee!.copyWith(isOnSite: onSite);
          }
        });
        ref.invalidate(currentEmployeeProvider);
        _resetTabIfHiddenModule();
      }
    }

    await Future.wait([
      _loadFleetSettings(preferServer: true),
      _loadWasteSettings(preferServer: true),
      _loadSecuritySettings(preferServer: true),
    ]);
    _retryFailedModuleSettings();
    _rearmActiveJobsStreamIfStuck();
    // My Work: four-stream merge can stick on cache-only empty after a rules/
    // claims blip — drop the cached stream so the tab re-subscribes cleanly.
    if (mounted && _myWorkStream != null) {
      setState(() {
        _myWorkStream = null;
        _myWorkClockNo = null;
      });
    }
    DeviceHealthService().syncPermissionsToFirestore();

    // Always re-fetch on resume so a force publish while backgrounded still blocks
    // (24h silent cooldown must not hide newly required upgrades).
    if (!kIsWeb && mounted) {
      try {
        await UpdateService().checkForUpdateOnResume(context);
      } catch (e) {
        debugPrint('Update check on resume: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadShowDeptOnly();
    _loadTestMode();
    _loadFleetSettings();
    _loadWasteSettings();
    _loadSecuritySettings();
    // Offline cold start: re-attempt any module-settings load that failed
    // the moment connectivity returns (only failed ones — no extra reads).
    _moduleSettingsConnSub =
        ConnectivityService().connectivityStream.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _retryFailedModuleSettings();
      }
    });

    if (realEmployee != null) {
      isOnSite = realEmployee!.isOnSite;
      _previousIsOnSite = realEmployee!.isOnSite;
      _setupEmployeeStream(realEmployee!.clockNo);
    } else {
      _tryLoadCurrentEmployee();
    }

    if (!kIsWeb) {
      _notificationService.refreshToken();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          // First pass (may lack employee for cohort match).
          await UpdateService().checkForUpdate(context);
        } catch (e) {
          debugPrint('Update check error: $e');
        }
        // Re-resolve channels once employee clock/dept are available.
        if (mounted &&
            (currentEmployee != null || realEmployee != null)) {
          try {
            await UpdateService().checkForUpdateIgnoringCooldown(context);
          } catch (e) {
            debugPrint('Update cohort re-check: $e');
          }
        } else if (mounted) {
          // Profile still loading — re-check when stream/stub fills in.
          _pendingCohortUpdateRecheck = true;
        }
        try {
          await NotificationService().checkPendingJobNavigation();
        } catch (e) {
          debugPrint('Pending job navigation error: $e');
        }
        try {
          await NotificationService().checkPendingFleetNavigation();
        } catch (e) {
          debugPrint('Pending fleet navigation error: $e');
        }
        // After update + deep-link handling: one-time "What's changed" sheet
        // when this is the first launch of a new build. Skips itself if a
        // deep link pushed a screen over Home.
        if (mounted) {
          await WhatsNewService().maybeShowWhatsNew(context);
        }
      });
    }

    try {
      _setupActiveJobsSubscription();
    } catch (e) {
      debugPrint('Error setting up job count subscription: $e');
    }

    if (kIsWeb && isManager) {
      // Review count: open+inProgress only (closed jobs don't need review)
      _reviewCountSubscription = _firestoreService.getOpenJobCards().listen((jobs) {
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
      }, onError: (e) {
        debugPrint('HomeScreen: review count stream error: $e');
      });
    }

    if (!kIsWeb) _setupFirebaseMessaging();
    if (kIsWeb) ClientPlatformService().syncToFirestore();
  }

  @override
  void dispose() {
    _employeeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _countSubscription?.cancel();
    _inProgressSub?.cancel();
    _reviewCountSubscription?.cancel();
    _messagingSubscription?.cancel();
    _moduleSettingsConnSub?.cancel();
    _testModeTimer?.cancel();
    _presenceNoticeDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    try {
      _messagingSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (!mounted) return;
        if (message.data['notificationType'] == 'assigned') {
          _setShellTab(1);
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

  /// Registry admin only, home tab only — opens UI persona picker (no tap hint).
  Future<void> _handleTitleLongPress(BuildContext context) async {
    if (_selectedIndex != 0) return;
    if (!await isRegistryAdmin()) return;
    if (!context.mounted) return;
    await showPersonaPickerDialog(context, ref);
  }

  // Feedback moved to its own surface (submit + follow status/replies) so the
  // loop closes: see MyFeedbackScreen + FeedbackThreadScreen.
  void _openMyFeedback() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyFeedbackScreen()),
    );
  }

  Widget _buildModuleHubCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(_isDesktop ? 24 : 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: _isDesktop ? 40 : 36, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: _isDesktop ? 18 : 17,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityGuardHomeHub() {
    final wasteIdx = _wasteTabIndex();
    final securityIdx = _securityTabIndex();
    final name = currentEmployee?.name ?? 'Guard';
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GeofenceHealthBanner(),
        Text(
          'Hello, $name',
          style: TextStyle(
            fontSize: _isDesktop ? 22 : 20,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _canUseOnSiteModules
              ? 'Your work is in Site Security and Waste Recovery. '
                'Open a module below — the app opens Security by default.'
              : 'Waste and Security are available on-site only. '
                'Return to the factory to open your modules.',
          style: TextStyle(
            fontSize: 14,
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Your modules',
          style: TextStyle(
            fontSize: _isDesktop ? 18 : 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        if (securityIdx >= 0)
          _buildModuleHubCard(
            title: 'Site Security',
            subtitle: 'Gate scans, company cars, visitors',
            icon: Icons.shield_outlined,
            color: kBrandOrange,
            onTap: () => _setShellTab(securityIdx),
          ),
        if (wasteIdx >= 0)
          _buildModuleHubCard(
            title: 'Waste Recovery',
            subtitle: 'Incoming loads, begin collections, stock',
            icon: Icons.delete_outline,
            color: const Color(0xFF2D6A4F),
            onTap: () => _setShellTab(wasteIdx),
          ),
        if (wasteIdx < 0 && securityIdx < 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _canUseOnSiteModules
                  ? 'No modules are enabled for your account. Ask an admin to turn on '
                    'Waste or Site Security in CTP Pulse Settings.'
                  : 'Waste and Security are available on-site only. '
                    'Return to the factory to open your modules.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildHomeTab() {
    if (_isSiteSecurityGuardOnly) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          _screenPadding,
          _screenPadding,
          _screenPadding,
          _screenPadding +
              ScreenInsets.scrollBottomInHomeShell(
                clearFab: !(_isOnWasteTab || _isOnFleetTab || _isOnSecurityTab),
              ),
        ),
        child: _buildSecurityGuardHomeHub(),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        _screenPadding,
        _screenPadding,
        _screenPadding,
        _screenPadding +
            ScreenInsets.scrollBottomInHomeShell(
              clearFab: !(_isOnWasteTab || _isOnFleetTab || _isOnSecurityTab),
            ),
      ),
      child: Column(
        children: [
          // Nudges the user if Location-Always / battery-opt got revoked, which
          // silently breaks background geofencing (hidden on web + when healthy).
          const GeofenceHealthBanner(),
          // One-shot status — banner only when incomplete (no live multi-stream).
          if (_canUseOnSiteModules &&
              role_utils.isInkMeterUser(currentEmployee)) ...[
            ref.watch(inkDailyReadingsStatusProvider).when(
                  data: (status) {
                    if (status.complete) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkDailyReadingsBanner(status: status),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
          ],
          Center(
            child: Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: _isDesktop ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildQuickActionsGrid(),

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
                        activeThumbColor: kBrandOrange,
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

  /// Tile width for Quick Actions — matches [SliverGridDelegateWithMaxCrossAxisExtent]
  /// on wide layouts so tiles don't balloon, but uses the phone column count below 600px.
  double _quickActionTileWidth(double availableWidth) {
    if (_isDesktop || _isTablet) {
      final maxExtent = _isDesktop ? 210.0 : 200.0;
      final columns = ((availableWidth + _gridSpacing) / (maxExtent + _gridSpacing))
          .ceil()
          .clamp(1, 99);
      return (availableWidth - _gridSpacing * (columns - 1)) / columns;
    }
    return (availableWidth - _gridSpacing * (_gridColumns - 1)) / _gridColumns;
  }

  Widget _buildQuickActionsGrid() {
    final workReportSettings =
        ref.watch(workReportSettingsProvider).valueOrNull;
    final tiles = <Widget>[
      ..._quickActions(workReportSettings).map((action) => _buildQuickActionCard(
            action['title'] as String,
            action['icon'] as IconData,
            action['color'] as Color,
            action['onTap'] as VoidCallback,
            disabledReason: action['disabledReason'] as String?,
            badgeCount: action['badgeCount'] as int?,
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
    ];

    // Wrap + center on every breakpoint so a partial row (e.g. three mechanic
    // tiles on a wide web window) sits in the middle instead of hugging the left
    // edge. GridView left-aligns spare columns, which is what the screenshot showed.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = _quickActionTileWidth(constraints.maxWidth);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: _gridSpacing,
          runSpacing: _gridSpacing,
          children: tiles
              .map((tile) => SizedBox(
                    width: tileWidth,
                    height: _gridTileHeight,
                    child: tile,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color, VoidCallback onTap,
      {String? disabledReason, int? badgeCount}) {
    final disabled = disabledReason != null;
    // Flat tile tinted with its group colour (wash + matching border) so
    // linked tiles read as a set. Disabled tiles fall back to a neutral
    // surface. See _quickActions for the group→colour mapping.
    final scheme = Theme.of(context).colorScheme;
    final tileColor = disabled
        ? scheme.surfaceContainerHighest
        : color.withValues(alpha: 0.12);
    final borderColor =
        disabled ? scheme.outlineVariant : color.withValues(alpha: 0.45);
    Widget card = Card(
      elevation: 0,
      color: tileColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 0.8),
      ),
      child: InkWell(
        // Disabled tiles explain themselves instead of doing nothing.
        onTap: disabled
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(disabledReason),
                    backgroundColor: Colors.orange[800],
                    duration: const Duration(seconds: 5),
                  ),
                )
            : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: _cardPaddingInsets,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Icon(icon, size: _iconSize, color: disabled ? Colors.grey : color),
                  if (disabled)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(Icons.location_off, size: _iconSize * 0.35, color: Colors.red[400]),
                    ),
                ],
              ),
              SizedBox(height: _isDesktop || _isTablet ? 6 : 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                  color: disabled
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    if (badgeCount != null && badgeCount > 0) {
      card = Stack(
        fit: StackFit.expand,
        children: [
          card,
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: Text(
                badgeCount.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }
    return card;
  }

  /// Skeleton placeholder for the recent-jobs section; [waitingForServer]
  /// adds a hint that the app is offline/reconnecting — a cached-empty
  /// snapshot must never masquerade as "No recent jobs available".
  Widget _buildRecentJobsPlaceholder({required bool waitingForServer}) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              const SkeletonLoader(height: 80),
              const SizedBox(height: 12),
              const SkeletonLoader(height: 80),
              const SizedBox(height: 12),
              const SkeletonLoader(height: 80),
              if (waitingForServer) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Waiting for connection…',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentJobCards() {
    // Renders from _activeJobsSnap — the single shared open+inProgress
    // listener owned by _countSubscription (see initState). No inline stream:
    // a stream created in build re-subscribes Firestore on every rebuild.
    final snap = _activeJobsSnap;
    switch (decideListLoadState(
      hasSnapshot: snap != null,
      isEmpty: snap?.cards.isEmpty ?? true,
      isFromCache: snap?.isFromCache ?? true,
    )) {
      case ListLoadState.loading:
        return _buildRecentJobsPlaceholder(waitingForServer: false);
      case ListLoadState.waitingForServer:
        return _buildRecentJobsPlaceholder(waitingForServer: true);
      case ListLoadState.empty:
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text('No recent jobs available', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        );
      case ListLoadState.data:
        break;
    }

            final allJobs = snap!.cards;

            var recentJobs = allJobs
                .toList()
              ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

            var topJobs = recentJobs.take(30).toList();

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
                  Expanded(child: _buildStatusColumn('Open', openJobs, kBrandOrange)),
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
                  style: TextButton.styleFrom(foregroundColor: kBrandOrange),
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
                    style: TextButton.styleFrom(foregroundColor: kBrandOrange),
                  ),
                ),
              ],
            ),
          );
        }
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

    // Cache the stream per clockNo — an inline stream re-subscribes a fresh
    // Firestore listener on every rebuild and resets the resilient wrapper's
    // retry state. clockNo follows currentEmployee (persona-aware).
    final clockNo = currentEmployee!.clockNo;
    if (_myWorkStream == null || _myWorkClockNo != clockNo) {
      _myWorkClockNo = clockNo;
      _myWorkStream = _firestoreService.getMyJobCardsWithMeta(clockNo);
    }

    return StreamBuilder<JobCardListSnapshot>(
      stream: _myWorkStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }
        final meta = snapshot.data;
        switch (decideListLoadState(
          hasSnapshot: meta != null,
          isEmpty: meta?.cards.isEmpty ?? true,
          isFromCache: meta?.isFromCache ?? true,
        )) {
          case ListLoadState.loading:
            return const Center(child: CircularProgressIndicator());
          case ListLoadState.waitingForServer:
            // Cached-empty: the server hasn't answered yet — showing the
            // "Active (0)" tabs here reads as "my work vanished".
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for connection…',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () async {
                      await AuthClaimsService.refreshClaims();
                      if (!mounted) return;
                      setState(() {
                        _myWorkStream = null;
                        _myWorkClockNo = null;
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          case ListLoadState.empty:
          case ListLoadState.data:
            break; // server-confirmed — the tab bar below is truthful.
        }

        final all = meta!.cards;

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
      role_utils.isOperatorRestrictedForJob(currentEmployee, job);

  Future<void> _startWork(JobCard job) async {
    if (!guardPersonaSubmit(context)) return;
    final current = currentEmployee;
    if (current == null) return;
    final actor = resolveWriteActor(current)!;
    try {
      // Same implementation as the detail screen's Start — the old My Work
      // path set inProgress without assigning the user or writing history.
      await _actions.startJob(job, actor);
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
                      if (!guardPersonaSubmit(context)) return;
                      final current = currentEmployee;
                      if (current == null) return;
                      final actor = resolveWriteActor(current)!;
                      setDialogState(() => isCompleting = true);
                      try {
                        // Same field-scoped action as the detail screen —
                        // the old My Work path wrote the note into `notes`
                        // instead of `correctiveAction` and merge-set the
                        // whole document.
                        await _actions.completeJob(job, actor, note,
                            withMonitoring: false);

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
                      if (!guardPersonaSubmit(context)) return;
                      final current = currentEmployee;
                      if (current == null) return;
                      final actor = resolveWriteActor(current)!;
                      setDialogState(() => isMonitoring = true);
                      try {
                        await _actions.completeJob(job, actor, note,
                            withMonitoring: true);

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
                  padding: ScreenInsets.listPadding(
                    context,
                    inHomeShell: true,
                    clearFab: !(_isOnWasteTab || _isOnFleetTab || _isOnSecurityTab),
                  ),
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return JobCardTile(
                      job: job,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => JobCardDetailScreen(jobCard: job))),
                      actions: !_operatorRestrictedFor(job)
                          ? _buildMyWorkActionButtons(context, job)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMyWorkActionButtons(BuildContext context, JobCard job) {
    const btnPadding = EdgeInsets.symmetric(vertical: 10);
    if (job.startedAt == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _startWork(job),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.black,
            padding: btnPadding,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Start Work'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _showMyWorkCompleteDialog(context, job),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.black,
              padding: btnPadding,
              minimumSize: const Size(0, 44),
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
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Monitor'),
          ),
        ),
      ],
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

  /// Copper tab — only mounted when [isCopperAuthorized] (admin / Pre Press manager).
  /// No clock-number or password dialog; Firestore rules enforce the same gate.
  Widget _buildCopperTab() {
    return const CopperDashboardScreen();
  }

  void _setShellTab(int index) {
    if (!mounted) return;
    setState(() {
      final prev = _selectedIndex;
      _selectedIndex = index;
      // C5: drop My Work listener when leaving that tab.
      final myWorkIdx = _showMyWorkNav ? 1 : -1;
      if (myWorkIdx >= 0 && prev == myWorkIdx && index != myWorkIdx) {
        _myWorkStream = null;
        _myWorkClockNo = null;
      }
    });
  }

  void _onItemTapped(int index) {
    final tabCount = 1 +
        (_showMyWorkNav ? 1 : 0) +
        (_isCopperAuthorized ? 1 : 0) +
        (_showWasteModule ? 1 : 0) +
        (_isFleetUser ? 1 : 0) +
        (_showSecurityModule ? 1 : 0);
    if (index < 0 || index >= tabCount) return;
    _setShellTab(index);
  }

  // ---------------------------------------------------------------------------
  // WASTE TRACK placeholder tab (will become the dedicated home for Security roles)
  // ---------------------------------------------------------------------------
  Widget _buildWasteTab() {
    // Security roles land here directly (per approved plan)
    return const WasteHomeScreen();
  }

  // ---------------------------------------------------------------------------
  // FLEET MAINTENANCE tab
  // ---------------------------------------------------------------------------
  Widget _buildFleetTab() {
    return const FleetHomeScreen();
  }

  Widget _buildSecurityTab() {
    return const SecurityHomeScreen();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild shell tabs, quick actions, and nav when admin persona testing switches.
    ref.listen<PersonaState>(personaProvider, (prev, next) {
      if (prev?.employee?.clockNo != next.employee?.clockNo) {
        _myWorkStream = null;
        _myWorkClockNo = null;
        if (mounted) _setShellTab(0);
      }
    });
    ref.watch(personaProvider);

    ref.listen<AsyncValue<FleetSettings>>(fleetSettingsProvider, (_, next) {
      next.whenData((settings) {
        if (mounted && _cachedFleetSettings != settings) {
          setState(() => _cachedFleetSettings = settings);
          _maybeOpenFleetTabForMechanic();
          _loadFleetSettings();
        }
      });
    });

    if (_pendingJobId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleJobDeepLink(_pendingJobId!);
        _pendingJobId = null;
      });
    }

    // Ensure manager open-job listener arms after async employee load / persona switch.
    if (_needsActiveJobsListener && _countSubscription == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _needsActiveJobsListener && _countSubscription == null) {
          _setupActiveJobsSubscription();
        }
      });
    } else if (!_needsActiveJobsListener && _countSubscription != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_needsActiveJobsListener) {
          _setupActiveJobsSubscription();
        }
      });
    }

    final List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      if (_showMyWorkNav)
        const BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'My Work'),
      if (_isCopperAuthorized)
        const BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Copper'),
      if (_showWasteModule)
        const BottomNavigationBarItem(icon: Icon(Icons.delete_outline), label: 'Waste'),
      if (_isFleetUser)
        const BottomNavigationBarItem(icon: Icon(Icons.forklift), label: 'Fleet'),
      if (_showSecurityModule)
        const BottomNavigationBarItem(icon: Icon(Icons.shield_outlined), label: 'Security'),
    ];

    // Lazy builders — only the selected shell tab is mounted so module
    // Firestore listeners dispose when switching away (C3 / C5).
    final List<Widget Function()> tabBuilders = [
      () => _buildHomeTab(),
      if (_showMyWorkNav) () => _buildMyWorkTab(),
      if (_isCopperAuthorized) () => _buildCopperTab(),
      if (_showWasteModule) () => _buildWasteTab(),
      if (_isFleetUser) () => _buildFleetTab(),
      if (_showSecurityModule) () => _buildSecurityTab(),
    ];

    if (_selectedIndex >= tabBuilders.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _selectedIndex == 0
              ? () => _handleTitleLongPress(context)
              : null,
          child: Text(_appBarTitle),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kBrandOrange, isOnSite ? Colors.green : Colors.red],
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
          if (realEmployee != null)
            Builder(
              builder: (ctx) {
                final count = ref.watch(
                  unreadInboxCountProvider(realEmployee!.clockNo),
                );
                return IconButton(
                  icon: Badge(
                    label: count > 0 ? Text('$count') : null,
                    isLabelVisible: count > 0,
                    child: const Icon(Icons.notifications_outlined,
                        color: Colors.black),
                  ),
                  tooltip: 'Notification Inbox',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationInboxScreen()),
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
          const SessionHealthBanner(),
          const UpdateAvailableBanner(),
          const PersonaBanner(),
          const SyncIndicator(),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: tabBuilders[_selectedIndex](),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: ScreenInsets.spacing),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: items,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      ),
      floatingActionButton: (_isOnCopperTab ||
              _isOnWasteTab ||
              _isOnFleetTab ||
              _isOnSecurityTab)
          ? null
          : FloatingActionButton(
              onPressed: _openMyFeedback,
              backgroundColor: kBrandOrange,
              tooltip: 'Feedback',
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

    // Gold/amber to match the manager group in Quick Actions; the orange→red
    // pulse still overrides it when the review backlog is over threshold.
    const amber = Color(0xFFEAB308);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glowColor = isPulsing
            ? Color.lerp(Colors.orange, Colors.red, _glowAnim.value)!
            : Colors.transparent;

        return Transform.scale(
          scale: isPulsing ? _scaleAnim.value : 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Card(
                elevation: isPulsing ? _glowAnim.value * 6 : 0,
                color: amber.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: isPulsing
                      ? BorderSide(
                          color: glowColor.withValues(
                              alpha: 0.4 + _glowAnim.value * 0.6),
                          width: 2.0,
                        )
                      : BorderSide(
                          color: amber.withValues(alpha: 0.45), width: 0.8),
                ),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: widget.padding,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_late_outlined,
                          size: widget.iconSize,
                          color: isPulsing ? glowColor : amber,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Daily Review',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
