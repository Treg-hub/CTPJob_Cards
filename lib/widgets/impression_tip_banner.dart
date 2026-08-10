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
        'Everyone sees what is on press, spares, and outstanding work. '
        'Only your department can action its section (Mechanical / Electrical / Pressroom). '
        'Managers and admin can pick who did the work when recording history, and adjust date/time. '
        'Always remove a roller before installing a spare.',
    'daily_ir':
        'Enter pressures for every unit that has a roller. Empty units are skipped. '
        'If a reading is over max, record the action (drop pressure or plan a change). '
        'Use the condition chips; choose Other for free text.',
    'daily_esa':
        'Yellow units have no ESA — they are skipped. Clean charge and discharge '
        '(or pressure roller on Badenia), then pick a condition. Other opens free text.',
    'start_build':
        'Shaft (roller) number is required. Tick unnumbered if the sleeve has no number yet. '
        '“Built by / bearings fitted by” is who built the roller (paper field). '
        'Result defaults to FAIL — tap PASS only when mechanical is good so Electrical can test.',
    'electrical':
        'Enter cold conductive (mΩ) and insulation (GΩ) readings. '
        'PASS = OK for any unit. FAIL = yellow (no-ESA) units only. No extra ESA dropdown.',
    'cycle_detail':
        'Life of this roller build: who did mechanical and electrical, install and remove, '
        'a simple timeline, and daily IR/ESA while it was on the press.',
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
