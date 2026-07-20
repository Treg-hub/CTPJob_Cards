import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../theme/app_theme.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';

/// In-app Lurgi operator guide (floor capture). Full markdown: docs/lurgi_operator_guide.md.
class LurgiOperatorGuideScreen extends StatelessWidget {
  const LurgiOperatorGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Lurgi guide');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lurgi guide')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Lurgi operator guide')),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          Card(
            color: appColors.lurgiSurface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Morning plant meters, effluent chemicals, recycling runs, '
                'and ink/toloul Daily Readings. Capture at the time you stand '
                'at the dial — operators cannot backdate (admins can for support).',
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _h(context, '1. Start of day'),
          _p(context,
              'Open the Lurgi hub. Status shows morning sections (5), Daily Readings, chemicals, and recycling.'),
          _p(context,
              'Walk the plant using the Daily log tiles — one area at a time: Gas/Boiler → Fresh & Effluent → Air → Geyser → Toloul Tanks. Save each section before the next.'),
          _p(context,
              'If a meter dial rolled over, tick “Meter was reset”. If the last capture was not yesterday, read the multi-day warning and add a short note.'),
          const SizedBox(height: 12),
          _h(context, '2. Daily Readings (ink + toloul)'),
          _p(context,
              'Open Daily Readings when you can complete meters. Blank fields are skipped. If you only finish some meters, return later and use “Add missing readings” — already-done meters stay locked.'),
          _p(context,
              'To correct a wrong reading, a manager voids the session on CTP Pulse first. Do not invent a second reading for the same meter the same day.'),
          const SizedBox(height: 12),
          _h(context, '3. Chemicals & recycling'),
          _p(context,
              'Log effluent chemicals as you dose (day total = sum of entries). Log each recycling machine cycle with start/finish times, steam, litres, dirty level, and cleaned if true.'),
          _p(context,
              'If nothing is needed today, use “No dosing today” / “No recycling today” so the desk knows you did not forget.'),
          _p(context,
              'Wrong entry? Use Request void + reason. Totals still include it until a manager voids on Pulse. Do not double-enter to “fix”.'),
          const SizedBox(height: 12),
          _h(context, '4. Ink Factory recovery (view only)'),
          _p(context,
              'Recovery posts are from Ink Factory into the factory tank. Lurgi only views them for the open count period. Do not post toloul stock from Lurgi. Recycling machine litres are separate from ledger recovery.'),
          const SizedBox(height: 12),
          _h(context, '5. Tips'),
          _p(context,
              'Unsaved forms draft until end of calendar day (survive app close). Operator tips on screens can be dismissed with “Don’t show again”.'),
          _p(context,
              'Period history shows open-count chemicals, recycling, recovery, and morning completion. Closed periods: CTP Pulse Lurgi desk.'),
          const SizedBox(height: 24),
          Text(
            'Full written guide: mobile app docs → lurgi_operator_guide.md',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget _h(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  static Widget _p(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.bodyMedium),
      );
}
