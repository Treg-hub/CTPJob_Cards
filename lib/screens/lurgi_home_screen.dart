import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../providers/ink_provider.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import 'ink_daily_readings_screen.dart';
import 'lurgi_chemicals_screen.dart';
import 'lurgi_ink_factory_recovery_screen.dart';
import 'lurgi_period_history_screen.dart';
import 'lurgi_recycling_screen.dart';
import 'lurgi_section_form.dart';

/// Lurgi department hub — morning ops, multi-entry logs, Daily Readings, recovery view.
class LurgiHomeScreen extends ConsumerWidget {
  const LurgiHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Lurgi');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lurgi')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final round = ref.watch(lurgiTodayRoundProvider).valueOrNull;
    final readings = ref.watch(inkDailyReadingsStatusProvider).valueOrNull;
    final chemTotals = ref.watch(lurgiTodayChemicalTotalsProvider);
    final recycleSummary = ref.watch(lurgiTodayRecyclingSummaryProvider);
    final morningDone = round?.morningComplete ?? false;
    final morningParts = round?.completedSectionCount ?? 0;
    final qty = NumberFormat('#,##0.##');
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Lurgi')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(lurgiTodayRoundProvider);
          ref.invalidate(inkDailyReadingsStatusProvider);
          ref.invalidate(lurgiTodayChemicalUsageProvider);
          ref.invalidate(lurgiTodayRecyclingRunsProvider);
          await ref.read(lurgiTodayRoundProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            ScreenInsets.scrollBottomFullScreen(context),
          ),
          children: [
            _StatusCard(
              morningDone: morningDone,
              morningParts: morningParts,
              morningTotal: LurgiDailyRound.totalSections,
              readingsDone: readings?.complete ?? false,
              readingsLabel: readings?.bannerMessage,
              chemicalEntries: chemTotals.entryCount,
              chemicalTotalKg: chemTotals.totalKg,
              recyclingRuns: recycleSummary.runCount,
              recyclingLitres: recycleSummary.totalLitresRecycled,
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Morning'),
            const SizedBox(height: 8),
            _ActionGrid(actions: [
              _Action(
                Icons.wb_sunny_outlined,
                'Morning Round',
                badge: morningDone
                    ? 'Done'
                    : '$morningParts/${LurgiDailyRound.totalSections}',
                badgeOk: morningDone,
                builder: () =>
                    const LurgiSectionFormScreen(section: LurgiSection.all),
              ),
              _Action(
                Icons.speed_outlined,
                'Daily Readings',
                badge: readings == null
                    ? null
                    : (readings.complete ? 'Done' : 'Todo'),
                badgeOk: readings?.complete ?? false,
                builder: () => const InkDailyReadingsScreen(),
              ),
            ]),
            const SizedBox(height: 20),
            _sectionLabel(context, 'Daily logs'),
            const SizedBox(height: 8),
            _ActionGrid(actions: [
              _Action(
                Icons.propane_tank_outlined,
                'Toloul Tanks',
                badge: (round?.tanksComplete ?? false) ? 'Done' : null,
                badgeOk: round?.tanksComplete ?? false,
                builder: () =>
                    const LurgiSectionFormScreen(section: LurgiSection.tanks),
              ),
              _Action(
                Icons.local_fire_department_outlined,
                'Gas / Boiler / Softener',
                badge: (round?.utilitiesComplete ?? false) ? 'Done' : null,
                badgeOk: round?.utilitiesComplete ?? false,
                builder: () => const LurgiSectionFormScreen(
                    section: LurgiSection.utilities),
              ),
              _Action(
                Icons.water_drop_outlined,
                'Fresh & Effluent',
                badge: (round?.waterComplete ?? false) ? 'Done' : null,
                badgeOk: round?.waterComplete ?? false,
                builder: () =>
                    const LurgiSectionFormScreen(section: LurgiSection.water),
              ),
              _Action(
                Icons.ac_unit_outlined,
                'Air Condenser',
                badge: (round?.airComplete ?? false) ? 'Done' : null,
                badgeOk: round?.airComplete ?? false,
                builder: () =>
                    const LurgiSectionFormScreen(section: LurgiSection.air),
              ),
              _Action(
                Icons.thermostat_outlined,
                'Geyser',
                badge: (round?.geyserComplete ?? false) ? 'Done' : null,
                badgeOk: round?.geyserComplete ?? false,
                builder: () =>
                    const LurgiSectionFormScreen(section: LurgiSection.geyser),
              ),
            ]),
            const SizedBox(height: 20),
            _sectionLabel(context, 'As needed'),
            const SizedBox(height: 8),
            _ActionGrid(actions: [
              _Action(
                Icons.science_outlined,
                'Effluent Chemicals',
                badge: chemTotals.entryCount == 0
                    ? null
                    : '${chemTotals.entryCount} · ${qty.format(chemTotals.totalKg)} kg',
                badgeOk: chemTotals.entryCount > 0,
                builder: () => const LurgiChemicalsScreen(),
              ),
              _Action(
                Icons.recycling_outlined,
                'Recycling Machine',
                badge: recycleSummary.runCount == 0
                    ? null
                    : '${recycleSummary.runCount} · ${qty.format(recycleSummary.totalLitresRecycled)} L',
                badgeOk: recycleSummary.runCount > 0,
                builder: () => const LurgiRecyclingScreen(),
              ),
            ]),
            const SizedBox(height: 20),
            _sectionLabel(context, 'Ink Factory'),
            const SizedBox(height: 8),
            _ActionGrid(actions: [
              _Action(
                Icons.visibility_outlined,
                'Ink Factory Recovery',
                builder: () => const LurgiInkFactoryRecoveryScreen(),
              ),
              _Action(
                Icons.history,
                'Period history',
                builder: () => const LurgiPeriodHistoryScreen(),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              'Recovery and period history use the open ink count window '
              '(since last month-end). Closed periods: CTP Pulse Lurgi desk.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: appColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionLabel(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.morningDone,
    required this.morningParts,
    required this.morningTotal,
    required this.readingsDone,
    this.readingsLabel,
    this.chemicalEntries = 0,
    this.chemicalTotalKg = 0,
    this.recyclingRuns = 0,
    this.recyclingLitres = 0,
  });

  final bool morningDone;
  final int morningParts;
  final int morningTotal;
  final bool readingsDone;
  final String? readingsLabel;
  final int chemicalEntries;
  final double chemicalTotalKg;
  final int recyclingRuns;
  final double recyclingLitres;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    final scheme = Theme.of(context).colorScheme;
    final allOk = morningDone && readingsDone;
    // Soft themed fills — never light text on light fill.
    final surface =
        allOk ? appColors.wasteGreenSurface : appColors.lurgiSurface;
    final border =
        allOk ? appColors.wasteGreenDark : appColors.lurgiDark;
    final titleColor =
        allOk ? appColors.wasteGreenDark : appColors.lurgiDark;
    final bodyColor = scheme.onSurface;
    final qty = NumberFormat('#,##0.##');
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              allOk ? 'Morning capture complete' : 'Morning capture',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lurgi meters: $morningParts / $morningTotal sections'
              '${morningDone ? ' ✓' : ''}',
              style: TextStyle(color: bodyColor),
            ),
            const SizedBox(height: 2),
            Text(
              readingsDone
                  ? 'Ink / Toloul daily readings: done ✓'
                  : (readingsLabel ?? 'Ink / Toloul daily readings: not done'),
              style: TextStyle(color: bodyColor),
            ),
            const SizedBox(height: 6),
            Text(
              chemicalEntries == 0
                  ? 'Chemicals: no entries yet today'
                  : 'Chemicals: $chemicalEntries entr${chemicalEntries == 1 ? 'y' : 'ies'} · ${qty.format(chemicalTotalKg)} kg',
              style: TextStyle(color: bodyColor),
            ),
            Text(
              recyclingRuns == 0
                  ? 'Recycling: no runs yet today'
                  : 'Recycling: $recyclingRuns run${recyclingRuns == 1 ? '' : 's'} · ${qty.format(recyclingLitres)} L',
              style: TextStyle(color: bodyColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(
    this.icon,
    this.label, {
    this.builder,
    this.badge,
    this.badgeOk = false,
  });
  final IconData icon;
  final String label;
  final Widget Function()? builder;
  final String? badge;
  final bool badgeOk;
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions});
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in actions)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 24 - 16) / 3,
            child: _ActionCard(action: a),
          ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});
  final _Action action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    // Module accent on surfaceContainerHighest (not brand orange primary).
    final iconColor = appColors.lurgiAccent;
    final badgeColor =
        action.badgeOk ? appColors.statusCompleted : appColors.lurgiAccent;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (action.builder != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => action.builder!()),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(action.icon, color: iconColor),
              const SizedBox(height: 6),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
              ),
              if (action.badge != null) ...[
                const SizedBox(height: 4),
                Text(
                  action.badge!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
