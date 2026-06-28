import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/device_health_service.dart';

/// Home banner when any critical device permission is missing — geofence,
/// battery, notifications, DND, overlay, or P5 full-screen intent.
///
/// Re-checks on app resume. Hidden on web and when fully healthy.
class GeofenceHealthBanner extends StatefulWidget {
  const GeofenceHealthBanner({super.key});

  /// Alias for clearer imports in new code.
  static const deviceHealth = GeofenceHealthBanner;

  @override
  State<GeofenceHealthBanner> createState() => _GeofenceHealthBannerState();
}

/// Preferred name — same widget as [GeofenceHealthBanner].
typedef DeviceHealthBanner = GeofenceHealthBanner;

class _GeofenceHealthBannerState extends State<GeofenceHealthBanner>
    with WidgetsBindingObserver {
  DeviceHealthSnapshot? _snapshot;
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
    final snap = await DeviceHealthService().check();
    if (!mounted) return;
    setState(() => _snapshot = snap);
  }

  Future<void> _fix() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DeviceHealthService().requestMissing();
      await DeviceHealthService().syncPermissionsToFirestore();
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    if (kIsWeb || snap == null || snap.isFullyHealthy) {
      return const SizedBox.shrink();
    }
    final missing = snap.missingLabels.join('  +  ');
    final title = snap.isGeofenceHealthy
        ? 'Some alerts may not reach you'
        : 'On-site alerts may not work';
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
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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