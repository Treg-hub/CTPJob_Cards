import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/device_health_service.dart';
import '../theme/app_theme.dart';

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
      await DeviceHealthService().fixMissing();
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final missing = snap.missingLabels.join('  +  ');
    final title = snap.isGeofenceHealthy
        ? 'Some alerts may not reach you'
        : 'On-site alerts may not work';

    // Hardcoded orange.shade50 + theme-default text fails in dark mode (white on
    // pale orange). Pick explicit surfaces + label colors per brightness.
    final backgroundColor =
        isDark ? const Color(0xFF2C1D0E) : const Color(0xFFFFF3E0);
    final borderColor =
        isDark ? kBrandOrange : const Color(0xFFFFB74D);
    final iconColor =
        isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final bodyColor =
        isDark ? const Color(0xFFFFE0B2) : const Color(0xFF4E342E);
    const fixButtonBg = Color(0xFFE65100);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap Fix and allow: $missing',
                  style: TextStyle(fontSize: 12, color: bodyColor, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _fix,
            style: FilledButton.styleFrom(
              backgroundColor: fixButtonBg,
              foregroundColor: Colors.white,
              disabledBackgroundColor: fixButtonBg.withValues(alpha: 0.55),
              disabledForegroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Fix',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}