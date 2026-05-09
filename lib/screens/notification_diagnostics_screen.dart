import 'package:flutter/material.dart';
import 'package:ctp_job_cards/services/location_service.dart';
import 'package:ctp_job_cards/services/notification_service.dart';

class NotificationDiagnosticsScreen extends StatefulWidget {
  const NotificationDiagnosticsScreen({super.key});

  @override
  State<NotificationDiagnosticsScreen> createState() => _NotificationDiagnosticsScreenState();
}

class _NotificationDiagnosticsScreenState extends State<NotificationDiagnosticsScreen> {
  Map<String, bool> _permissions = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    final service = NotificationService();
    final result = await service.checkAllCriticalPermissions();
    setState(() {
      _permissions = result;
      _isLoading = false;
    });
  }

  Future<void> _testFullscreen() async {
    await NotificationService().testFullscreenNotification();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Test full-screen notification sent!")),
    );
  }

  Future<void> _testGeoFenceLog(bool isEntering) async {
    final locationService = LocationService();
    await locationService.logTestGeoFenceEvent(
      isEntering: isEntering,
      notes: 'Manual test from Diagnostics screen',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEntering 
            ? '✅ Test ENTER logged to geo_fence_logs + isOnSite updated' 
            : '📍 Test EXIT logged to geo_fence_logs + isOnSite updated'
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notification Diagnostics")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text("Permission Status", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ..._permissions.entries.map((entry) => ListTile(
                    title: Text(entry.key),
                    trailing: Icon(
                      entry.value ? Icons.check_circle : Icons.cancel,
                      color: entry.value ? Colors.green : Colors.red,
                    ),
                  )),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _testFullscreen,
              icon: const Icon(Icons.notifications_active),
              label: const Text("Test Fullscreen Notification (Priority 5)"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkPermissions,
              child: const Text("Refresh Permission Status"),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const Text("GeoFence Logging Test", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _testGeoFenceLog(true),
                    icon: const Icon(Icons.login),
                    label: const Text("Test ENTER (Onsite)"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _testGeoFenceLog(false),
                    icon: const Icon(Icons.logout),
                    label: const Text("Test EXIT (Offsite)"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              "Writes to geo_fence_logs collection + updates isOnSite flag",
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
