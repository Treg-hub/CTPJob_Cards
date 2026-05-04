import 'package:flutter/material.dart';
import 'package:ctp_job_cards/services/notification_service.dart';

class TestNotificationScreen extends StatefulWidget {
  const TestNotificationScreen({super.key});

  @override
  State<TestNotificationScreen> createState() => _TestNotificationScreenState();
}

class _TestNotificationScreenState extends State<TestNotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  String _status = "Ready to test";

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      await _notificationService.initialize();
      setState(() => _status = "✅ NotificationService initialized successfully");
    } catch (e) {
      setState(() => _status = "❌ Initialization failed: $e");
    }
  }

  Future<void> _runTest(String testName, Future<void> Function() testFunction) async {
    setState(() => _status = "Running: $testName...");
    try {
      await testFunction();
      setState(() => _status = "✅ $testName completed successfully");
    } catch (e) {
      setState(() => _status = "❌ $testName failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notification Test Panel"),
        backgroundColor: Colors.red.shade900,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: Colors.grey.shade900,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text("STATUS", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // PRIORITY 5 TESTS
            const Text("PRIORITY 5 (URGENT)", 
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text("Test Persistent Banner (Foreground P5)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _runTest(
                "Persistent Banner",
                () => _notificationService.testPersistentBanner(),
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton.icon(
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text("Test Fullscreen Alarm (Background Simulation)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _runTest(
                "Fullscreen Alarm",
                () => _notificationService.testFullscreenNotification(),
              ),
            ),

            const SizedBox(height: 24),

            // OTHER TESTS
            const Text("OTHER LEVELS", 
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              icon: const Icon(Icons.notifications),
              label: const Text("Test Normal Notification"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _runTest(
                "Normal Notification",
                () => _notificationService.showOnSiteNotification(
                  title: "Normal Job Update",
                  body: "This is a standard notification test",
                ),
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton.icon(
              icon: const Icon(Icons.volume_up),
              label: const Text("Test Medium-High (Priority 4)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _runTest(
                "Medium-High",
                () => _notificationService.showLocalNotification(
                  title: "Medium Priority Job",
                  body: "This requires attention soon (simulated medium-high)",
                  level: 'medium-high',
                  jobCardNumber: "999",
                  priority: "4",
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("TESTING INSTRUCTIONS", 
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 8),
                  Text("• Persistent Banner: Should feel normal, not too loud"),
                  Text("• Fullscreen Alarm: Simulates background/locked behavior"),
                  Text("• Lock your phone and test real P5 to see full-screen UI"),
                  Text("• Check notification shade after each test"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}