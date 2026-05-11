import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
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

  final List<Widget> _pages = [
    const _WelcomePage(),
    const _HowItWorksPage(),
    const _JobCardFlowPage(),
    const _PriorityLevelsPage(),
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
  const _WelcomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.work, size: 80, color: Color(0xFFFF8C42)),
          const SizedBox(height: 30),
          const Text("Welcome to\nCTP Job Cards", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          const Text("We built this app to make your day easier and help you never miss an important job again.", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }
}

// PAGE 2 - How It Works
class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("How It Works", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          _buildFlowStep("1", "You arrive at site", Icons.location_on, Colors.green),
          const SizedBox(height: 12),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 12),
          _buildFlowStep("2", "We detect you're onsite (within 800m)", Icons.gps_fixed, Colors.blue),
          const SizedBox(height: 12),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 12),
          _buildFlowStep("3", "You get instant loud alerts (even on silent)", Icons.notifications_active, Colors.orange),
          const SizedBox(height: 12),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 12),
          _buildFlowStep("4", "When you leave, you're marked offsite", Icons.logout, Colors.red),
          const SizedBox(height: 30),
          const Text("This means you never miss urgent jobs again.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildFlowStep(String number, String text, IconData icon, Color color) {
    return Row(
      children: [
        CircleAvatar(radius: 20, backgroundColor: color, child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        const SizedBox(width: 16),
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}

// PAGE 3 - Creating & Completing a Job Card (Corrected)
class _JobCardFlowPage extends StatelessWidget {
  const _JobCardFlowPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Creating & Completing Jobs", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          _buildStep("1", "Operator creates a job card"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("2", "You get notified instantly based on department and priority"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("3", "Tap 'Assign to Me' or 'Busy'"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("4", "Complete the job + upload photos"),
          const SizedBox(height: 8),
          const Icon(Icons.arrow_downward, color: Colors.grey),
          const SizedBox(height: 8),
          _buildStep("5", "Job is saved to your history"),
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

// PAGE 4 - Notification Priority Levels (Corrected with Priority 4)
class _PriorityLevelsPage extends StatelessWidget {
  const _PriorityLevelsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Notification Priority Levels", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _buildPriorityCard("Normal", Colors.blue, "Regular job assignments", "Normal sound + vibration"),
          const SizedBox(height: 12),
          _buildPriorityCard("Priority 4 - Persistent Banner", Colors.orange, "Important jobs (Priority 4)", "Loud sound + red banner that stays on screen"),
          const SizedBox(height: 12),
          _buildPriorityCard("Priority 5 - Full Screen", Colors.red, "Urgent / Critical jobs", "Very loud + full screen takeover + bypasses DND"),
          const SizedBox(height: 24),
          const Text("You will experience all three. The higher the priority, the more attention it demands.", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildPriorityCard(String title, Color color, String when, String behavior) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text("When: $when", style: const TextStyle(fontSize: 14)),
          Text("Behavior: $behavior", style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

// PAGE 5 - Permissions + Test Buttons
class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text("Let's Set This Up", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text("We need these permissions so the app can work properly for you:", textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            _buildPermissionItem("Notifications (Priority 5)", "Get loud, full-screen alerts even when your phone is on silent"),
            _buildPermissionItem("Location (Always)", "Know when you're onsite so you get the right jobs"),
            _buildPermissionItem("Display over other apps", "Urgent jobs can take over your screen"),
            _buildPermissionItem("Camera", "Quickly upload photos of completed work"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
              child: const Text("⚠️ If you don't grant these permissions, the app will NOT work to its full ability. You may miss urgent jobs.", style: TextStyle(color: Colors.orange, fontSize: 14), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 24),
            const Text("Test the Different Notification Levels", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildTestButton(context, "Test Normal Notification", Colors.blue, () => NotificationService().testNormalNotification(), "Standard job assignment alert"),
            const SizedBox(height: 10),
            _buildTestButton(context, "Test Persistent Banner (Priority 4)", Colors.orange, () => NotificationService().testMediumHighNotification(), "Priority 4 style - stays on screen"),
            const SizedBox(height: 10),
            _buildTestButton(context, "Test P5 Full Screen Alert", Colors.red, () => NotificationService().testFullLoudNotification(), "Highest priority - full screen + alarm"),
            const SizedBox(height: 16),
            const Text("Try all three to see the difference", style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 22),
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