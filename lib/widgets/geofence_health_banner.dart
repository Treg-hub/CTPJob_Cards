import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Home/Settings banner that keeps the two permissions which make background
/// geofencing work — Location "Allow all the time" and the battery-optimisation
/// exemption — granted over time, not just at onboarding. Users silently
/// downgrade these and then stop getting on-site alerts; this surfaces it.
///
/// Hidden on web and when both are already granted. Re-checks on app resume
/// (so it disappears as soon as the user fixes it in system Settings).
class GeofenceHealthBanner extends StatefulWidget {
  const GeofenceHealthBanner({super.key});

  @override
  State<GeofenceHealthBanner> createState() => _GeofenceHealthBannerState();
}

class _GeofenceHealthBannerState extends State<GeofenceHealthBanner>
    with WidgetsBindingObserver {
  bool _locationAlways = true;
  bool _batteryOk = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      _refresh();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final loc = await Permission.locationAlways.status;
    final bat = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) return;
    setState(() {
      _locationAlways = loc.isGranted;
      _batteryOk = bat.isGranted;
    });
  }

  Future<void> _fix() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Android 10+: when-in-use must be granted before "always".
      if (!(await Permission.locationWhenInUse.status).isGranted) {
        await Permission.locationWhenInUse.request();
      }
      final always = await Permission.locationAlways.status;
      if (!always.isGranted) {
        final res = await Permission.locationAlways.request();
        // Android 11+ won't re-prompt for "always" via dialog — open Settings.
        if (!res.isGranted &&
            (res.isPermanentlyDenied || always.isPermanentlyDenied)) {
          await openAppSettings();
        }
      }
      if ((await Permission.ignoreBatteryOptimizations.status).isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (_locationAlways && _batteryOk)) {
      return const SizedBox.shrink();
    }
    final missing = <String>[
      if (!_locationAlways) 'Location “Allow all the time”',
      if (!_batteryOk) 'Battery optimisation off',
    ].join('  +  ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(children: [
        const Icon(Icons.location_off_outlined, color: Colors.orange, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('On-site alerts may not work',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text('Tap Fix and allow: $missing',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy ? null : _fix,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Fix'),
        ),
      ]),
    );
  }
}
