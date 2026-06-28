import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show currentEmployee;
import '../models/employee.dart';
import '../providers/current_employee_provider.dart';
import '../providers/permissions_provider.dart';
import '../services/device_health_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../utils/role.dart';
import '../models/fleet_settings.dart';
import '../models/waste_settings.dart';
import '../services/fleet_service.dart';
import '../services/waste_service.dart';
import 'home_screen.dart';

class PermissionsOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  ConsumerState<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState
    extends ConsumerState<PermissionsOnboardingScreen> {
  int _currentPage = 0;
  bool _isLoading = false;
  final PageController _pageController = PageController();

  // Live geofence radius from the central `settings/geofence` doc, so the
  // onboarding copy always matches the real barrier instead of a hard-coded "800 m".
  int _radiusMeters = kDefaultGeofence.radius.round();

  @override
  void initState() {
    super.initState();
    loadGeofenceConfig().then((cfg) {
      if (mounted) setState(() => _radiusMeters = cfg.radius.round());
    });
  }

  // Fired when the user taps "Next" — requests the permissions explained by the
  // page they are LEAVING, awaiting each system dialog so it is resolved BEFORE
  // the next screen appears. By the time the final permissions-status page is
  // reached, every permission has already been requested in context, so that
  // page is purely a status display.
  Future<void> _requestPermsForLeavingPage(int leavingPage) async {
    if (kIsWeb) return;
    switch (leavingPage) {
      case 2:
        // Just read how job cards are created & completed — photos are attached
        // as evidence, so request the camera in that context.
        await _requestCameraPerm();
      case 4:
        // Just read Priority Levels (P4 DND bypass, P5 full-screen alarm).
        // Request the alert-delivery permissions that make those behaviours work.
        await _requestAlertPerms();
      case 5:
        // Just read Escalation: you're only alerted while on site, which is
        // driven by background geofencing. Request location + battery now.
        await _requestLocationPerms();
    }
    ref.invalidate(permissionsProvider);
  }

  Future<void> _requestCameraPerm() async {
    if (!(await Permission.camera.status).isGranted) {
      await Permission.camera.request();
    }
  }

  // Notifications, Do Not Disturb bypass, and the full-screen overlay —
  // everything needed to deliver P4 (DND bypass) and P5 (full-screen) alerts.
  Future<void> _requestAlertPerms() async {
    if (!(await Permission.notification.status).isGranted) {
      await Permission.notification.request();
    }
    if (!(await Permission.accessNotificationPolicy.status).isGranted) {
      await Permission.accessNotificationPolicy.request();
    }
    if (!(await Permission.systemAlertWindow.status).isGranted) {
      await Permission.systemAlertWindow.request();
    }
  }

  Future<void> _requestLocationPerms() async {
    // Android 10+: must grant when-in-use before always.
    if (!(await Permission.locationWhenInUse.status).isGranted) {
      await Permission.locationWhenInUse.request();
    }
    if (!(await Permission.locationAlways.status).isGranted) {
      await Permission.locationAlways.request();
    }
    // Keeps background geofencing alive so on-site detection keeps working.
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // Drives forward navigation. Requests the leaving page's permissions and
  // awaits them before animating to the next page, so the system dialogs always
  // appear on the explaining screen — never on the final status screen.
  Future<void> _handleNext(int lastIndex) async {
    if (_currentPage >= lastIndex) {
      await _completeOnboarding();
      return;
    }
    final leaving = _currentPage;
    setState(() => _isLoading = true);
    try {
      await _requestPermsForLeavingPage(leaving);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // Rebuilt every frame from the latest employee value so the role page reflects
  // the right role even if the employee provider resolves after this screen mounts.
  List<Widget> _buildPages(Employee? emp) => [
        const _WelcomePage(),
        _YourRolePage(role: roleFromEmployee(emp), employee: emp),
        const _JobCardFlowPage(),
        const _JobStatusPage(),
        const _PriorityLevelsPage(),
        _EscalationPage(radiusMeters: _radiusMeters),
        _PermissionsPage(radiusMeters: _radiusMeters),
      ];

  Future<void> _completeOnboarding() async {
    setState(() => _isLoading = true);

    if (!kIsWeb) {
      final health = await DeviceHealthService().check();
      if (!health.isOnboardingCoreHealthy && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Some permissions still missing'),
            content: Text(
              'Without location, battery, and notification access you may miss '
              'urgent on-site alerts.\n\nStill missing:\n'
              '${health.missingLabels.map((l) => '• $l').join('\n')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go back'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx, false);
                  await DeviceHealthService().fixMissing();
                  ref.invalidate(permissionsProvider);
                },
                child: const Text('Open Settings'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C42),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final locationGranted =
        kIsWeb ? false : (await Permission.locationAlways.status).isGranted;

    // Onboarding is shown once; revoked permissions are handled via Home banner.
    await prefs.setBool('permissionsCompleted', true);

    if (!kIsWeb) {
      await DeviceHealthService().syncPermissionsToFirestore();
    }

    if (!kIsWeb && currentEmployee != null && locationGranted) {
      try {
        await LocationService().startNativeMonitoring(currentEmployee!.clockNo);
        debugPrint('✅ Native monitoring started after onboarding');
      } catch (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st,
            reason: 'native_monitoring_start_post_onboarding');
      }
      await LocationService().checkCurrentLocation();
    }

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the live employee value. Falls back to the global mutable
    // `currentEmployee` from main.dart so this screen still works during the
    // brief window after registration before the provider has resolved.
    final emp =
        ref.watch(currentEmployeeProvider).valueOrNull ?? currentEmployee;
    final pages = _buildPages(emp);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_currentPage + 1) / pages.length,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFFFF8C42),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                // Swipe is disabled so navigation is button-driven: that lets the
                // Next handler request a page's permissions and await them BEFORE
                // advancing. The Back/Next buttons are the only way to move.
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut),
                        child: const Text("Back")),
                  const Spacer(),
                  ElevatedButton(
                    onPressed:
                        _isLoading ? null : () => _handleNext(pages.length - 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C42),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFFF8C42).withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _currentPage == pages.length - 1
                                ? "Let's Get Started"
                                : "Next",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// PAGE 1 - Welcome
class _WelcomePage extends StatelessWidget {
  const _WelcomePage();
  @override
  Widget build(BuildContext context) {
    final name = currentEmployee?.name ?? '';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.work, size: 80, color: Color(0xFFFF8C42)),
          const SizedBox(height: 30),
          Text(
            name.isEmpty ? "Welcome to\nCTP Job Cards" : "Welcome,\n$name",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text(
            "We built this app to make your day easier and help you never miss an important job again.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// PAGE 2 - Your Role in CTP (role-aware, including specialized roles)
class _YourRolePage extends StatefulWidget {
  final UserRole role;
  final Employee? employee;
  const _YourRolePage({required this.role, this.employee});

  @override
  State<_YourRolePage> createState() => _YourRolePageState();
}

class _YourRolePageState extends State<_YourRolePage> {
  WasteSettings? _wasteSettings;
  FleetSettings? _fleetSettings;

  @override
  void initState() {
    super.initState();
    WasteService().getWasteSettings().then((settings) {
      if (mounted) setState(() => _wasteSettings = settings);
    });
    FleetService().getSettings().then((settings) {
      if (mounted) setState(() => _fleetSettings = settings);
    });
  }

  UserRole get role => widget.role;
  Employee? get employee => widget.employee;

  // Specialized role checks take priority over the base UserRole so that
  // a Security Guard (maps to 'operator') or Hyster Mechanic (maps to
  // 'technician') sees content relevant to their actual day-to-day module.
  bool get _isSecurityManager => isSecurityManager(employee, _wasteSettings);
  bool get _isSecurityGuard => isSecurityGuard(employee, _wasteSettings);
  bool get _isFleetMechanic => isFleetMechanic(employee, _fleetSettings);

  String get _title {
    if (_isSecurityManager) return "You're a Security Manager";
    if (_isSecurityGuard) return "You're a Security Guard";
    if (_isFleetMechanic) return "You're the Hyster Mechanic";
    return switch (role) {
      UserRole.technician => "You're a Technician",
      UserRole.manager => "You're a Manager",
      UserRole.admin => "You're an Admin",
      UserRole.operator => "You're an Operator",
    };
  }

  String get _subtitle {
    if (_isSecurityManager) {
      return "You oversee every waste load that leaves the factory — collections, weights, contractors, and reports.";
    }
    if (_isSecurityGuard) {
      return "You process waste collections at the gate — beginning the load, recording items, and signing off at the weighbridge.";
    }
    if (_isFleetMechanic) {
      return "You maintain the Hyster machines on site — your work queue lives in the Fleet tab.";
    }
    return switch (role) {
      UserRole.technician =>
        "You receive jobs, attend to faults, and close them out.",
      UserRole.manager =>
        "You oversee jobs, enforce quality, and respond to escalations.",
      UserRole.admin =>
        "You configure the system — employees, geofences, escalation rules.",
      UserRole.operator => "You report faults — the first link in the chain.",
    };
  }

  IconData get _icon {
    if (_isSecurityManager) return Icons.security;
    if (_isSecurityGuard) return Icons.badge;
    if (_isFleetMechanic) return Icons.forklift;
    return switch (role) {
      UserRole.technician => Icons.build,
      UserRole.manager => Icons.dashboard,
      UserRole.admin => Icons.admin_panel_settings,
      UserRole.operator => Icons.report,
    };
  }

  List<_RoleBullet> get _bullets {
    if (_isSecurityManager) {
      return const [
        _RoleBullet(Icons.add_box_outlined,
            "Schedule waste collections: contractor, waste types, and expected date"),
        _RoleBullet(Icons.inventory_2,
            "Browse on-site stock and Copper ready to sell — IBC bins and copper appear here when thresholds are met"),
        _RoleBullet(Icons.link,
            "On collection day, link saved stock via Begin Collection → From stock"),
        _RoleBullet(Icons.checklist,
            "Pending weighbridge and cost review are completed on CTP Pulse, not mobile"),
      ];
    }
    if (_isSecurityGuard) {
      return const [
        _RoleBullet(Icons.local_shipping,
            "When a contractor arrives, find their scheduled load in the Waste tab and tap Begin Collection"),
        _RoleBullet(Icons.link,
            "Link saved stock on collection day with From stock — you won't browse the stock inventory list"),
        _RoleBullet(Icons.photo_camera,
            "Record each item with photos — weighted types need kg; IBC bins and quantity-only types need a count"),
        _RoleBullet(Icons.draw,
            "Capture the contractor driver's signature before the truck leaves when required"),
      ];
    }
    if (_isFleetMechanic) {
      return const [
        _RoleBullet(Icons.list_alt,
            "Your Fleet tab shows all open issues sorted by severity — Out of Service jobs appear first"),
        _RoleBullet(Icons.touch_app,
            "Tap a fault in To Fix to Mark as Fixed — the issue is acknowledged when you open it, then resolved when you save the fix"),
        _RoleBullet(Icons.engineering,
            "Work records capture labour hours, machine hour-meter reading, parts used, and photos — numbered FM-####"),
        _RoleBullet(Icons.money_off,
            "You never see cost amounts — a cost manager handles that separately"),
      ];
    }
    return switch (role) {
      UserRole.technician => const [
          _RoleBullet(Icons.notifications_active,
              "Receive job alerts the moment a fault is reported in your trade and you're on site"),
          _RoleBullet(Icons.touch_app,
              "Tap 'Assign to Me' on the notification — the job moves to In-Progress and escalation stops"),
          _RoleBullet(Icons.location_on,
              "Background location must be 'Allow All the Time' — without it you'll miss alerts when off-screen"),
          _RoleBullet(Icons.check_circle_outline,
              "Close jobs with a clear note — what was done, parts used, root cause"),
        ],
      UserRole.manager => const [
          _RoleBullet(Icons.dashboard,
              "Manager Dashboard shows live status of every job in your department"),
          _RoleBullet(Icons.fact_check,
              "Daily Review (web) lets you scope jobs by department or type and add manager notes"),
          _RoleBullet(Icons.notification_important,
              "If Stage 2 escalation fires, you're notified — that's your cue to act"),
          _RoleBullet(Icons.history,
              "Notification History logs every alert sent and every response received"),
        ],
      UserRole.admin => const [
          _RoleBullet(Icons.settings,
              "Open the gear icon and unlock Admin with your password"),
          _RoleBullet(Icons.people_outline,
              "Employees / Structures / Escalation Config / Job Cards — all editable from the Admin screen"),
          _RoleBullet(Icons.timer,
              "Escalation rule changes go live on the next 2-minute Cloud Function tick"),
          _RoleBullet(Icons.map,
              "Geofence Editor configures on-site boundaries directly on the device"),
        ],
      UserRole.operator => const [
          _RoleBullet(Icons.add_circle_outline,
              "When something breaks, create a job card immediately — no paper, no radio"),
          _RoleBullet(Icons.edit_note,
              "Be specific: machine name, what you observed, accurate priority"),
          _RoleBullet(Icons.schedule,
              "If no technician responds within 5 minutes, escalation kicks in automatically"),
          _RoleBullet(Icons.notifications,
              "You'll receive 'no response yet' follow-ups so you know the system is chasing it"),
        ],
    };
  }

  Color get _accent {
    if (_isSecurityManager || _isSecurityGuard) {
      return const Color(0xFF10B981); // green
    }
    if (_isFleetMechanic) return const Color(0xFF0EA5E9); // sky blue
    return switch (role) {
      UserRole.technician => const Color(0xFF10B981),
      UserRole.manager => const Color(0xFF3B82F6),
      UserRole.admin => const Color(0xFF8B5CF6),
      UserRole.operator => const Color(0xFFFF8C42),
    };
  }

  // Closing note varies: specialized roles need a nudge that the job-card
  // pages ahead still apply to them (they're on site, so they get alerts too).
  String get _closingNote {
    if (_isSecurityManager) {
      return "The next few pages cover job cards, priorities, and escalation — you'll still receive on-site notifications and can report faults too.";
    }
    if (_isSecurityGuard) {
      return "The next few pages cover the job card system — you may still receive on-site notifications, so this context is useful.";
    }
    if (_isFleetMechanic) {
      return "The next few pages cover the standard job card system — as an operator you can still report and receive plant job cards too.";
    }
    return "The next few pages explain how job cards, priorities, and escalation work — everyone uses these the same way.";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Icon(_icon, size: 64, color: _accent),
            const SizedBox(height: 14),
            Text(_title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.grey)),
            const SizedBox(height: 22),
            ..._bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(b.icon, color: _accent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(b.text,
                              style: const TextStyle(fontSize: 15))),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                _closingNote,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBullet {
  final IconData icon;
  final String text;
  const _RoleBullet(this.icon, this.text);
}

// One permission described in a _PermissionPreface row.
class _PermDetail {
  final IconData icon;
  final String name;
  final String reason;
  const _PermDetail(this.icon, this.name, this.reason);
}

// A callout placed at the bottom of an explanation page, telling the user
// exactly which permission(s) the app is about to request when they tap "Next".
// Requests are fired by the Next handler immediately after this is read, so the
// user always sees what is being asked — and why — before the system dialog.
class _PermissionPreface extends StatelessWidget {
  final List<_PermDetail> perms;
  const _PermissionPreface({required this.perms});

  static const Color accent = Color(0xFFFF8C42);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'When you tap "Next", the app will ask for:',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...perms.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(p.icon, size: 20, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 1),
                          Text(p.reason,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          Text(
            'You can also change these later in your phone Settings.',
            style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// PAGE 3 - Creating & Completing a Job Card
class _JobCardFlowPage extends StatelessWidget {
  const _JobCardFlowPage();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            const Text("Creating & Completing Jobs",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            _buildStep("1",
                "Operator creates a job card with machine, fault, and priority"),
            const SizedBox(height: 8),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 8),
            _buildStep("2",
                "On-site technicians of the right trade are notified instantly"),
            const SizedBox(height: 8),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 8),
            _buildStep("3",
                "Tap 'Assign to Me' (job → In-Progress, escalation stops) or 'Busy'"),
            const SizedBox(height: 8),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 8),
            _buildStep("4",
                "If no one responds, escalation fires — managers are notified"),
            const SizedBox(height: 8),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 8),
            _buildStep("5",
                "Job is worked, closed with a note, and saved permanently"),
            const SizedBox(height: 30),
            const Text("Everything happens in one app. No WhatsApp. No paper.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
            const SizedBox(height: 24),
            const _PermissionPreface(
              perms: [
                _PermDetail(
                  Icons.camera_alt_outlined,
                  "Camera",
                  "Attach before/after photos as evidence directly on a job card. The app never uses your camera in the background.",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Row(
      children: [
        CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFFF8C42),
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold))),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}

// PAGE 4 - Job Card Status Flow
class _JobStatusPage extends StatelessWidget {
  const _JobStatusPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Job Card Status",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                "Every job moves through four stages from creation to completion.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
            const SizedBox(height: 28),
            _buildStatusCard("Open", Colors.blue,
                "Job created — awaiting a technician to accept it. Escalation timers are running."),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStatusCard("In-Progress", Colors.orange,
                "You tapped 'Assign Self' — the job is now yours. Escalation stops immediately."),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStatusCard("Monitor", Colors.amber,
                "Fault resolved but the machine is being watched for recurrence before final closure."),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStatusCard("Closed", Colors.green,
                "Fault confirmed resolved. Closure note recorded. Operator is notified."),
            const SizedBox(height: 20),
            const Text(
                "Tip: The status moves from Open to In-Progress automatically when you accept the job. You only need to set Monitor or Closed yourself.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String label, Color color, String description) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(100)),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(description, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// PAGE 5 - Notification Priority Levels P1-P5
class _PriorityLevelsPage extends StatelessWidget {
  const _PriorityLevelsPage();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Priority Levels P1–P5",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Priority drives how loudly the system alerts. Operators: choose honestly — a P5 means production is standing.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _buildPriorityCard(
              "P1 — No impact",
              Colors.blue,
              "Routine or planned work",
              "Normal banner, default sound",
            ),
            const SizedBox(height: 10),
            _buildPriorityCard(
              "P2 — Minor impact",
              Colors.lightBlue,
              "Can continue, attend soon",
              "Normal banner, default sound",
            ),
            const SizedBox(height: 10),
            _buildPriorityCard(
              "P3 — Moderate impact",
              Colors.amber,
              "Attend within the shift",
              "Banner with action buttons, default sound",
            ),
            const SizedBox(height: 10),
            _buildPriorityCard(
              "P4 — Significant impact",
              Colors.orange,
              "Attend as soon as possible",
              "Persistent banner, custom sound, DND bypass",
            ),
            const SizedBox(height: 10),
            _buildPriorityCard(
              "P5 — Production standing",
              Colors.red,
              "Immediate response required",
              "Full-screen alarm, loud, lock-screen takeover, DND bypass",
            ),
            const SizedBox(height: 16),
            const Text(
              "The higher the priority, the more attention the system demands. Operators decide — pick the level that matches actual production impact.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),
            const _PermissionPreface(
              perms: [
                _PermDetail(
                  Icons.notifications_active_outlined,
                  "Notifications",
                  "Receive job alerts the moment a fault is reported for your trade.",
                ),
                _PermDetail(
                  Icons.do_not_disturb_on_outlined,
                  "Do Not Disturb access",
                  "Let P4 and P5 alerts reach you even when your phone is on silent or DND.",
                ),
                _PermDetail(
                  Icons.fullscreen,
                  "Display over other apps",
                  "Show the full-screen P5 alarm over whatever you're doing so a production stoppage can't be missed.",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityCard(
      String title, Color color, String when, String behavior) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text("When: $when", style: const TextStyle(fontSize: 13)),
          Text("Behaviour: $behavior", style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// PAGE 6 - How Escalation Works
class _EscalationPage extends StatelessWidget {
  final int radiusMeters;
  const _EscalationPage({required this.radiusMeters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text("How Escalation Works",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "If no technician responds, the system escalates automatically across four stages.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 22),
            _buildStageCard(
              stage: "Stage 1",
              time: "5 minutes",
              state: "Enabled by default",
              recipients: "On-site managers + foremen for the job's department",
              color: const Color(0xFFFBBF24),
            ),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStageCard(
              stage: "Stage 2",
              time: "10 minutes",
              state: "Enabled by default",
              recipients:
                  "On-site dept managers + workshop manager (urgent alert)",
              color: const Color(0xFFFB923C),
            ),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStageCard(
              stage: "Stage 3",
              time: "30 minutes",
              state: "Disabled by default — admin can enable",
              recipients: "Configurable (typically senior management)",
              color: const Color(0xFFEF4444),
              dimmed: true,
            ),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStageCard(
              stage: "Stage 4",
              time: "60 minutes",
              state: "Disabled by default — admin can enable",
              recipients: "Configurable (final escalation tier)",
              color: const Color(0xFFB91C1C),
              dimmed: true,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C42).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFF8C42).withValues(alpha: 0.3)),
              ),
              child: const Column(
                children: [
                  Text(
                    "Escalation stops the moment any technician taps 'Assign to Me' or 'I'm Busy'.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Admin can change timings, recipients, and on/off state under Settings → Escalation Rules. Operators also receive 'no response yet' follow-ups at each stage so they know the system is chasing it.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _PermissionPreface(
              perms: [
                _PermDetail(
                  Icons.location_on_outlined,
                  "Location — Allow all the time",
                  "Detects when you arrive on site (within $radiusMeters m) so you only get alerts for jobs you can attend. Background ('Allow all the time') access is required for this to work when the app is closed.",
                ),
                const _PermDetail(
                  Icons.battery_saver,
                  "Ignore battery optimisation",
                  "Keeps geofencing alive so on-site detection keeps working when your phone is idle.",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageCard({
    required String stage,
    required String time,
    required String state,
    required String recipients,
    required Color color,
    bool dimmed = false,
  }) {
    final opacity = dimmed ? 0.5 : 1.0;
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(stage,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(20)),
                  child: Text(time,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(state,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(recipients, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// PAGE 7 - Permissions + Test Buttons
class _PermissionsPage extends ConsumerStatefulWidget {
  final int radiusMeters;
  const _PermissionsPage({required this.radiusMeters});
  @override
  ConsumerState<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends ConsumerState<_PermissionsPage>
    with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WidgetsBinding.instance.addObserver(this);
    // Every permission was already requested in context on the earlier pages
    // (camera on the Job Card flow, alerts on Priority Levels, location on
    // Escalation). This page is purely a status display — just refresh the
    // live statuses so the rows reflect what the user granted on the way here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(permissionsProvider);
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(permissionsProvider);
    }
  }

  // Catch-all used by the "Grant Permissions" button — walks every required
  // permission and requests anything still missing, then opens Settings for
  // SAW if it remains denied after the system dialog.
  Future<void> _grantPermissions() async {
    if (kIsWeb) return;
    setState(() => _checking = true);
    try {
      await DeviceHealthService().fixMissing();
      if (!(await Permission.camera.status).isGranted) {
        await DeviceHealthService().fixPermission(Permission.camera);
      }
      await DeviceHealthService().syncPermissionsToFirestore();
    } finally {
      ref.invalidate(permissionsProvider);
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _requestSingle(Permission perm) async {
    if (kIsWeb) return;
    await DeviceHealthService().fixPermission(perm);
    await DeviceHealthService().syncPermissionsToFirestore();
    ref.invalidate(permissionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(requiredPermissionsProvider);
    final statusAsync = ref.watch(permissionsProvider);
    final statusMap =
        statusAsync.valueOrNull ?? const <Permission, PermissionStatus>{};
    final allGranted = items.isNotEmpty &&
        items.every((it) =>
            (statusMap[it.permission] ?? PermissionStatus.denied).isGranted);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text("Let's Set This Up",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              "We need these permissions so the app can work properly for you. Geofencing detects when you arrive on site (within ${widget.radiusMeters} m) so you only get alerts for jobs you can actually attend.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            for (final item in items)
              if (item.permission != null)
                _buildPermissionRow(
                  item: item,
                  granted:
                      (statusMap[item.permission!] ?? PermissionStatus.denied)
                          .isGranted,
                  onTapGrant: () => _requestSingle(item.permission!),
                ),
            const SizedBox(height: 16),
            if (!allGranted) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange)),
                child: const Text(
                    "⚠️ If you don't grant these permissions, the app will NOT work to its full ability. You may miss urgent jobs.",
                    style: TextStyle(color: Colors.orange, fontSize: 14),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _grantPermissions,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_open),
                  label: const Text("Grant Permissions",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C42),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text("All permissions granted!",
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            const Text("Test the Different Notification Levels",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildTestButton(
                context,
                "Test Normal Notification",
                Colors.blue,
                () => NotificationService().testNormalNotification(),
                "Standard job assignment alert (P1–P3)"),
            const SizedBox(height: 10),
            _buildTestButton(
                context,
                "Test Persistent Banner (P4)",
                Colors.orange,
                () => NotificationService().testMediumHighNotification(),
                "Priority 4 — stays on screen, DND bypass"),
            const SizedBox(height: 10),
            _buildTestButton(
                context,
                "Test P5 Full Screen Alert",
                Colors.red,
                () => NotificationService().testFullLoudNotification(),
                "Priority 5 — full-screen alarm, loud"),
            const SizedBox(height: 16),
            const Text("Try all three to see the difference",
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRow({
    required PermissionItem item,
    required bool granted,
    required VoidCallback onTapGrant,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: granted ? null : onTapGrant,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                granted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: granted ? Colors.green : Colors.grey,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(item.description,
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
              if (!granted)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right,
                      color: Color(0xFFFF8C42), size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestButton(BuildContext context, String label, Color color,
      VoidCallback onPressed, String description) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Column(
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
