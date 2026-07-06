import 'package:flutter/material.dart';
import '../main.dart' show currentEmployee;
import '../services/kiosk_mode_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';

/// Device-lockdown setup for a dedicated kiosk tablet (e.g. the main-gate
/// Site Security device). Locks the tablet to this app via Android Lock
/// Task Mode; getting out again requires either an admin login or the
/// device-specific exit code set up here. See KioskModeService for the two
/// protection tiers (Device Owner vs best-effort screen pinning).
class KioskModeScreen extends StatefulWidget {
  const KioskModeScreen({super.key});

  @override
  State<KioskModeScreen> createState() => _KioskModeScreenState();
}

class _KioskModeScreenState extends State<KioskModeScreen> {
  final _service = KioskModeService.instance;
  final _codeController = TextEditingController();
  final _confirmController = TextEditingController();
  final _unlockController = TextEditingController();

  bool _loading = true;
  bool _isDeviceOwner = false;
  bool _kioskEnabled = false;
  bool _hasCode = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _confirmController.dispose();
    _unlockController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final owner = await _service.isDeviceOwner();
    final enabled = await _service.isKioskModeEnabled();
    final hasCode = await _service.hasExitCodeConfigured();
    if (!mounted) return;
    setState(() {
      _isDeviceOwner = owner;
      _kioskEnabled = enabled;
      _hasCode = hasCode;
      _loading = false;
    });
  }

  bool get _isAdmin => currentEmployee?.isAdmin ?? false;

  Future<void> _saveExitCode() async {
    final code = _codeController.text.trim();
    final confirm = _confirmController.text.trim();
    if (code.length < 6) {
      _showMessage('Exit code must be at least 6 characters', error: true);
      return;
    }
    if (code != confirm) {
      _showMessage('Codes do not match', error: true);
      return;
    }
    setState(() => _busy = true);
    await _service.setExitCode(code);
    _codeController.clear();
    _confirmController.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hasCode = true;
    });
    _showMessage('Exit code saved on this device');
  }

  Future<void> _enableKiosk() async {
    if (!_hasCode) {
      _showMessage('Set an exit code first', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock this device?'),
        content: Text(
          _isDeviceOwner
              ? 'This tablet will be locked to CTP Job Cards only — no home '
                  'screen, no other apps, no status bar. Only the exit code '
                  'or an admin login can undo this.'
              : "This device isn't enrolled as Device Owner, so protection "
                  'is best-effort (standard Android screen pinning) — a '
                  'determined user can still exit via the system unpin '
                  'gesture. See the setup guide below for full lockdown.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lock Device'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    await _service.enterKioskMode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _kioskEnabled = true;
    });
  }

  Future<void> _unlock() async {
    if (_isAdmin) {
      setState(() => _busy = true);
      await _service.exitKioskMode();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _kioskEnabled = false;
      });
      _showMessage('Device unlocked');
      return;
    }

    final code = _unlockController.text.trim();
    if (code.isEmpty) {
      _showMessage('Enter the exit code', error: true);
      return;
    }
    setState(() => _busy = true);
    final lockout = await _service.lockoutRemaining();
    if (lockout != null) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(
        'Too many wrong codes — try again in ${lockout.inSeconds + 1}s',
        error: true,
      );
      return;
    }
    final ok = await _service.verifyExitCode(code);
    if (!ok) {
      final nowLocked = await _service.lockoutRemaining();
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(
        nowLocked != null
            ? 'Wrong code — locked out for ${nowLocked.inSeconds + 1}s'
            : 'Wrong code',
        error: true,
      );
      return;
    }
    await _service.exitKioskMode();
    _unlockController.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _kioskEnabled = false;
    });
    _showMessage('Device unlocked');
  }

  void _showMessage(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Light-shade tint fades to near-transparent in dark mode (matches the
    // Admin section pattern in settings_screen.dart) so the default theme
    // text color always has correct contrast against whatever's underneath,
    // instead of a fixed light background clashing with light theme text.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Kiosk Mode')),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          Card(
            color: (_isDeviceOwner ? Colors.green.shade50 : Colors.amber.shade50)
                .withValues(alpha: isDark ? 0.05 : 1.0),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _isDeviceOwner ? Icons.verified_user : Icons.warning_amber,
                    color: _isDeviceOwner ? Colors.green.shade700 : Colors.amber.shade800,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isDeviceOwner
                          ? 'Device Owner enrolled — full lockdown available'
                          : 'Not enrolled as Device Owner — only best-effort '
                              'screen pinning available. See setup guide below.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_kioskEnabled) ...[
            Text('This device is locked to Job Cards',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_isAdmin)
              ElevatedButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock (signed in as admin)'),
              )
            else ...[
              TextField(
                controller: _unlockController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Exit code'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock Device'),
              ),
            ],
          ] else if (_isAdmin) ...[
            Text('Set an exit code', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _hasCode
                  ? 'An exit code is already set on this device. Enter a new '
                      'one below to replace it.'
                  : 'Required before you can lock this device.',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New exit code (6+ characters)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm exit code'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy ? null : _saveExitCode,
              child: const Text('Save Exit Code'),
            ),
            const Divider(height: 32),
            Text('Lock this device', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _busy ? null : _enableKiosk,
              icon: const Icon(Icons.lock),
              label: const Text('Lock This Device to Job Cards'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              title: const Text('Full lockdown setup guide (Device Owner)'),
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    "For a tablet that can't be exited even via the system "
                    'unpin gesture:\n\n'
                    '1. Factory reset the tablet — no Google account may be '
                    'added yet.\n'
                    '2. Install this app via APK (skip Play Store / account '
                    'setup).\n'
                    '3. Connect via USB with ADB enabled and run:\n'
                    '   adb shell dpm set-device-owner '
                    'com.ctp.jobcards/.KioskDeviceAdminReceiver\n'
                    '4. Relaunch the app, sign in, then set an exit code and '
                    'tap "Lock This Device" above.\n\n'
                    'Without Device Owner, "Lock This Device" still pins the '
                    'app (Android screen pinning), but a user can exit via '
                    'the standard long-press back+recents gesture.',
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text('Ask an admin to set up Kiosk Mode on this device.'),
          ],
        ],
      ),
    );
  }
}
