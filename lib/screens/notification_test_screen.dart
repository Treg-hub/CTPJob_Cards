import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../utils/screen_insets.dart';

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  final NotificationService _notificationService = NotificationService();

  Future<void> _run(Future<void> Function() fn) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    NotificationService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Tests'),
        backgroundColor: const Color(0xFFFF8C42),
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Use these to verify notification delivery and permissions on this device.',
              style: TextStyle(fontSize: 14, color: Color(0xFF616161)),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fullscreen, color: Colors.red, size: 28),
              title: const Text('1. Full Screen Alert'),
              subtitle: const Text('Priority 5 — full-screen takeover, bypasses DND'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => _run(() => _notificationService.testFullLoudNotification()),
                child: const Text('TEST'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.notifications_active, color: Colors.orange, size: 28),
              title: const Text('2. Persistent Notification'),
              subtitle: const Text('Red persistent banner with action buttons'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange, foregroundColor: Colors.white),
                onPressed: () => _run(() => _notificationService.testMediumHighNotification()),
                child: const Text('TEST'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.notifications, color: Colors.blue, size: 28),
              title: const Text('3. General Notification'),
              subtitle: const Text('Standard job assignment / alert style'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: () => _run(() => _notificationService.testNormalNotification()),
                child: const Text('TEST'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
