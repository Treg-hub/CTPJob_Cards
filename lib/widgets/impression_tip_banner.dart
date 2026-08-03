import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';

/// Per-screen dismissible tip for Impression Rollers.
/// Keyed by [tipId] + clock so each employee can dismiss independently.
class ImpressionTipBanner extends StatefulWidget {
  const ImpressionTipBanner({
    super.key,
    required this.tipId,
    required this.text,
    this.icon = Icons.lightbulb_outline,
  });

  final String tipId;
  final String text;
  final IconData icon;

  static const Map<String, String> tips = {
    'hub':
        'Pick your press tab (remembered next time). Map shows what is in each unit. '
        'Your role only enables your steps — grey actions are for another department. '
        'Remove a roller first, then install a spare. Daily IR and ESA when the press is running.',
    'daily_ir':
        'Fill pressures for every occupied unit. Units awaiting install are skipped. '
        'If a reading is over max, note the action (drop pressure / plan change). '
        'Use condition chips; pick Other for free text.',
    'daily_esa':
        'Yellow units have no ESA. Clean charge/discharge (or pressure roller on Badenia), '
        'then pick condition chips. Other opens free text.',
    'start_build':
        'Shaft number is required. Sleeve can be unnumbered (system UNN). '
        'Complete mechanical measurements, then Pass so Electrical can test.',
    'electrical':
        'Enter conductive and insulation readings. Pass + Full ESA, or Yellow only if conductivity is weak. '
        'Fail keeps the assembly out of spares until rework.',
    'cycle_detail':
        'Full life of this build: mechanical, electrical, install/remove, events, and daily checks linked to this cycle.',
  };

  @override
  State<ImpressionTipBanner> createState() => _ImpressionTipBannerState();
}

class _ImpressionTipBannerState extends State<ImpressionTipBanner> {
  bool _visible = true;
  bool _loaded = false;

  String get _prefsKey {
    final clock = currentEmployee?.clockNo ?? 'anon';
    return 'impression_tip_dismissed_${widget.tipId}_$clock';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_prefsKey) ?? false;
    if (mounted) {
      setState(() {
        _visible = !dismissed;
        _loaded = true;
      });
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.10),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: kBrandOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            tooltip: 'Dismiss tip',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}
