import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee;
import '../services/kiosk_mode_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import 'kiosk_mode_screen.dart';
import 'notification_diagnostics_screen.dart';
import 'scan_tester_screen.dart';

/// Admin developer / device tools (Scan Tester, diagnostics, kiosk).
/// Feedback triage lives on Home Quick Actions for admins — not here.
class AdminToolsScreen extends StatefulWidget {
  const AdminToolsScreen({super.key});

  @override
  State<AdminToolsScreen> createState() => _AdminToolsScreenState();
}

class _AdminToolsScreenState extends State<AdminToolsScreen> {
  bool _kioskEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadKioskState();
  }

  Future<void> _loadKioskState() async {
    final enabled = await KioskModeService.instance.isKioskModeEnabled();
    if (mounted) setState(() => _kioskEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          Text(
            'DEVELOPER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            color: Theme.of(context).appColors.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF3B82F6)),
                  title: const Text('Scan Tester'),
                  subtitle: const Text(
                    'Capture raw barcode payloads for parser development',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final emp = currentEmployee;
                    if (emp == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Employee not loaded'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScanTesterScreen(employee: emp),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.bug_report, color: Colors.purple),
                  title: const Text('Notification Diagnostics'),
                  subtitle: const Text('Advanced fullscreen & permission testing'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationDiagnosticsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 24),
            Text(
              'DEVICE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: muted,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              color: Theme.of(context).appColors.cardSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(
                  _kioskEnabled ? Icons.lock : Icons.lock_outline,
                  color: Colors.deepOrange,
                ),
                title: Text(_kioskEnabled ? 'Kiosk Mode (locked)' : 'Kiosk Mode'),
                subtitle: Text(
                  _kioskEnabled
                      ? 'This device is locked to Job Cards — tap to manage'
                      : 'Lock this device to Job Cards only (main-gate tablets)',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const KioskModeScreen()),
                  );
                  if (mounted) _loadKioskState();
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'User feedback triage is on the Home Quick Actions tile for admins.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}
