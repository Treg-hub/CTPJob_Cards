import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show currentEmployee;
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../utils/role.dart';
import 'home_screen.dart';

class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  State<PermissionsOnboardingScreen> createState() => _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState extends State<PermissionsOnboardingScreen> {
  int _currentPage = 0;
  bool _isLoading = false;
  final PageController _pageController = PageController();

  late final List<Widget> _pages = [
    const _WelcomePage(),
    _YourRolePage(role: roleFromEmployee(currentEmployee)),
    const _JobCardFlowPage(),
    const _JobStatusPage(),
    const _PriorityLevelsPage(),
    const _EscalationPage(),
    const _PermissionsPage(),
  ];

  Future<void> _completeOnboarding() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissionsCompleted', true);
    await LocationService().checkCurrentLocation();

    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_currentPage + 1) / _pages.length,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFFFF8C42),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: _pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    TextButton(onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut), child: const Text("Back")),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _isLoading ? null : () {
                      if (_currentPage < _pages.length - 1) {
                        _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                      } else {
                        _completeOnboarding();
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_currentPage == _pages.length - 1 ? "Let's Get Started" : "Next", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

// PAGE 2 - Your Role in CTP (role-aware)
class _YourRolePage extends StatelessWidget {
  final UserRole role;
  const _YourRolePage({required this.role});

  String get _title => switch (role) {
        UserRole.technician => "You're a Technician",
        UserRole.manager => "You're a Manager",
        UserRole.admin => "You're an Admin",
        UserRole.operator => "You're an Operator",
      };

  String get _subtitle => switch (role) {
        UserRole.technician => "You receive jobs, attend to faults, and close them out.",
        UserRole.manager => "You oversee jobs, enforce quality, and respond to escalations.",
        UserRole.admin => "You configure the system — employees, geofences, escalation rules.",
        UserRole.operator => "You report faults — the first link in the chain.",
      };

  IconData get _icon => switch (role) {
        UserRole.technician => Icons.build,
        UserRole.manager => Icons.dashboard,
        UserRole.admin => Icons.admin_panel_settings,
        UserRole.operator => Icons.report,
      };

  List<_RoleBullet> get _bullets => switch (role) {
        UserRole.technician => const [
            _RoleBullet(Icons.notifications_active, "Receive job alerts the moment a fault is reported in your trade and you're on site"),
            _RoleBullet(Icons.touch_app, "Tap 'Assign to Me' on the notification — the job moves to In-Progress and escalation stops"),
            _RoleBullet(Icons.location_on, "Background location must be 'Allow All the Time' — without it you'll miss alerts when off-screen"),
            _RoleBullet(Icons.check_circle_outline, "Close jobs with a clear note — what was done, parts used, root cause"),
          ],
        UserRole.manager => const [
            _RoleBullet(Icons.dashboard, "Manager Dashboard shows live status of every job in your department"),
            _RoleBullet(Icons.fact_check, "Daily Review (web) lets you scope jobs by department or type and add manager notes"),
            _RoleBullet(Icons.notification_important, "If Stage 2 escalation fires, you're notified — that's your cue to act"),
            _RoleBullet(Icons.history, "Notification History logs every alert sent and every response received"),
          ],
        UserRole.admin => const [
            _RoleBullet(Icons.settings, "Open the gear icon and unlock Admin with your password"),
            _RoleBullet(Icons.people_outline, "Employees / Structures / Escalation Config / Job Cards — all editable from the Admin screen"),
            _RoleBullet(Icons.timer, "Escalation rule changes go live on the next 2-minute Cloud Function tick"),
            _RoleBullet(Icons.map, "Geofence Editor configures on-site boundaries directly on the device"),
          ],
        UserRole.operator => const [
            _RoleBullet(Icons.add_circle_outline, "When something breaks, create a job card immediately — no paper, no radio"),
            _RoleBullet(Icons.edit_note, "Be specific: machine name, what you observed, accurate priority"),
            _RoleBullet(Icons.schedule, "If no technician responds within 5 minutes, escalation kicks in automatically"),
            _RoleBullet(Icons.notifications, "You'll receive 'no response yet' follow-ups so you know the system is chasing it"),
          ],
      };

  Color get _accent => switch (role) {
        UserRole.technician => const Color(0xFF10B981),
        UserRole.manager => const Color(0xFF3B82F6),
        UserRole.admin => const Color(0xFF8B5CF6),
        UserRole.operator => const Color(0xFFFF8C42),
      };

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
            Text(_title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Colors.grey)),
            const SizedBox(height: 22),
            ..._bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(b.icon, color: _accent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Text(b.text, style: const TextStyle(fontSize: 15))),
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
              child: const Text(
                "The next few pages explain how job cards, priorities, and escalation work — everyone uses these the same way.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
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

// PAGE 3 - Creating & Completing a Job Card
class _JobCardFlowPage extends StatelessWidget {
  const _JobCardFlowPage();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Creating & Completing Jobs", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          _buildStep("1", "Operator creates a job card with machine, fault, and priority"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("2", "On-site technicians of the right trade are notified instantly"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("3", "Tap 'Assign to Me' (job → In-Progress, escalation stops) or 'Busy'"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("4", "If no one responds, escalation fires — managers are notified"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("5", "Job is worked, closed with a note, and saved permanently"),
          const SizedBox(height: 30),
          const Text("Everything happens in one app. No WhatsApp. No paper.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Row(
      children: [
        CircleAvatar(radius: 18, backgroundColor: const Color(0xFFFF8C42), child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
            const Text("Job Card Status", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Every job moves through four stages from creation to completion.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
            const SizedBox(height: 28),
            _buildStatusCard("Open", Colors.blue, "Job created — awaiting a technician to accept it. Escalation timers are running."),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStatusCard("In-Progress", Colors.orange, "You tapped 'Assign Self' — the job is now yours. Escalation stops immediately."),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStatusCard("Monitor", Colors.amber, "Fault resolved but the machine is being watched for recurrence before final closure."),
            const SizedBox(height: 10),
            const Icon(Icons.arrow_downward, color: Colors.grey),
            const SizedBox(height: 10),
            _buildStatusCard("Closed", Colors.green, "Fault confirmed resolved. Closure note recorded. Operator is notified."),
            const SizedBox(height: 20),
            const Text("Tip: The status moves from Open to In-Progress automatically when you accept the job. You only need to set Monitor or Closed yourself.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
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
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(description, style: const TextStyle(fontSize: 13))),
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
            const Text("Priority Levels P1–P5", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Priority drives how loudly the system alerts. Operators: choose honestly — a P5 means production is standing.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey),
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
              style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityCard(String title, Color color, String when, String behavior) {
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
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
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
  const _EscalationPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text("How Escalation Works", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
              recipients: "On-site dept managers + workshop manager (urgent alert)",
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
                border: Border.all(color: const Color(0xFFFF8C42).withValues(alpha: 0.3)),
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
                Text(stage, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                  child: Text(time, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(state, style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(recipients, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// PAGE 7 - Permissions + Test Buttons
class _PermissionsPage extends StatefulWidget {
  const _PermissionsPage();
  @override
  State<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<_PermissionsPage> {
  PermissionStatus _locationStatus = PermissionStatus.denied;
  PermissionStatus _notificationStatus = PermissionStatus.denied;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshStatuses().then((_) {
      if (!_locationStatus.isGranted || !_notificationStatus.isGranted) {
        _grantPermissions();
      }
    });
  }

  Future<void> _refreshStatuses() async {
    final loc = await Permission.locationAlways.status;
    final notif = await Permission.notification.status;
    if (mounted) setState(() { _locationStatus = loc; _notificationStatus = notif; });
  }

  Future<void> _grantPermissions() async {
    setState(() => _checking = true);
    if (!_locationStatus.isGranted) {
      final whenInUse = await Permission.locationWhenInUse.status;
      if (!whenInUse.isGranted) await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
    }
    if (!_notificationStatus.isGranted) await Permission.notification.request();
    await _refreshStatuses();
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final locationGranted = _locationStatus.isGranted;
    final notifGranted = _notificationStatus.isGranted;
    final allGranted = locationGranted && notifGranted;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text("Let's Set This Up", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              "We need these permissions so the app can work properly for you. Geofencing detects when you arrive on site (within 800 m) so you only get alerts for jobs you can actually attend.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            _buildPermissionRow("Location (Always)", "Know when you're onsite so you get the right jobs", locationGranted),
            _buildPermissionRow("Notifications", "Get loud, full-screen alerts even when your phone is on silent", notifGranted),
            _buildPermissionRow("Display over other apps", "Urgent jobs can take over your screen", true),
            _buildPermissionRow("Camera", "Quickly upload photos of completed work", true),
            const SizedBox(height: 16),
            if (!allGranted) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
                child: const Text("⚠️ If you don't grant these permissions, the app will NOT work to its full ability. You may miss urgent jobs.", style: TextStyle(color: Colors.orange, fontSize: 14), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _grantPermissions,
                  icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.lock_open),
                  label: const Text("Grant Permissions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text("All permissions granted!", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            const Text("Test the Different Notification Levels", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildTestButton(context, "Test Normal Notification", Colors.blue, () => NotificationService().testNormalNotification(), "Standard job assignment alert (P1–P3)"),
            const SizedBox(height: 10),
            _buildTestButton(context, "Test Persistent Banner (P4)", Colors.orange, () => NotificationService().testMediumHighNotification(), "Priority 4 — stays on screen, DND bypass"),
            const SizedBox(height: 10),
            _buildTestButton(context, "Test P5 Full Screen Alert", Colors.red, () => NotificationService().testFullLoudNotification(), "Priority 5 — full-screen alarm, loud"),
            const SizedBox(height: 16),
            const Text("Try all three to see the difference", style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRow(String title, String subtitle, bool granted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(granted ? Icons.check_circle : Icons.radio_button_unchecked, color: granted ? Colors.green : Colors.grey, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(BuildContext context, String label, Color color, VoidCallback onPressed, String description) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
