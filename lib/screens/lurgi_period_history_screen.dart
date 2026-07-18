import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../providers/ink_provider.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';

/// Open ink-count-period history for chemicals, recycling, and recovery.
/// Closed periods are reviewed on CTP Pulse (full count stepper).
class LurgiPeriodHistoryScreen extends ConsumerWidget {
  const LurgiPeriodHistoryScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM HH:mm');
  static final _day = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Period history');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Period history')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final periodFrom =
        ref.watch(inkSettingsProvider).valueOrNull?.latestActiveCountDate;
    final chemAsync = ref.watch(lurgiPeriodChemicalUsageProvider);
    final recycAsync = ref.watch(lurgiPeriodRecyclingRunsProvider);
    final recovAsync = ref.watch(lurgiInkFactoryRecoveriesProvider);
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Period history'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chemicals'),
              Tab(text: 'Recycling'),
              Tab(text: 'Recovery'),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                periodFrom == null
                    ? 'Open period: last 60 days (no month-end count on file). Full closed periods: CTP Pulse.'
                    : 'Open count period since ${_day.format(periodFrom)}. Closed periods: CTP Pulse.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: appColors.lurgiDark,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ListPane(
                    async: chemAsync,
                    empty: 'No chemical entries in this period.',
                    onRefresh: () async {
                      ref.invalidate(lurgiPeriodChemicalUsageProvider);
                      await ref.read(lurgiPeriodChemicalUsageProvider.future);
                    },
                    builder: (list) => [
                      for (final e in list)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              '${_qty.format(e.totalKg)} kg · ${_df.format(e.recordedAt)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'C ${_qty.format(e.causticSodaKg)} · '
                              'HCl ${_qty.format(e.hydrochloricAcidKg)} · '
                              'NaCl ${_qty.format(e.sodiumChlorideKg)} · '
                              'N ${_qty.format(e.naccolaintKg)}'
                              '${e.actorName.isNotEmpty ? ' · ${e.actorName}' : ''}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                    ],
                  ),
                  _ListPane(
                    async: recycAsync,
                    empty: 'No recycling runs in this period.',
                    onRefresh: () async {
                      ref.invalidate(lurgiPeriodRecyclingRunsProvider);
                      await ref.read(lurgiPeriodRecyclingRunsProvider.future);
                    },
                    builder: (list) => [
                      for (final r in list)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.recycling_outlined,
                                color: appColors.lurgiAccent),
                            title: Text(
                              '${_qty.format(r.litresRecycled)} L · ${_df.format(r.startAt)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'Dirty ${_qty.format(r.dirtyToloulLevelLitres)} L'
                              '${r.machineCleaned ? ' · cleaned' : ''}'
                              '${r.actorName.isNotEmpty ? ' · ${r.actorName}' : ''}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                    ],
                  ),
                  _ListPane(
                    async: recovAsync,
                    empty: 'No Ink recovery posts in this period.',
                    onRefresh: () async {
                      ref.invalidate(lurgiInkFactoryRecoveriesProvider);
                      await ref.read(lurgiInkFactoryRecoveriesProvider.future);
                    },
                    builder: (list) => [
                      for (final t in list)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.visibility_outlined,
                                color: appColors.lurgiAccent),
                            title: Text(
                              '${_qty.format(t.quantityDelta)} ${t.stockItemCode}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              [
                                _df.format(t.effectiveAt),
                                if (t.actorName.isNotEmpty) t.actorName,
                                if (t.seqNumber != null) t.seqNumber!,
                              ].join(' · '),
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListPane<T> extends StatelessWidget {
  const _ListPane({
    required this.async,
    required this.empty,
    required this.onRefresh,
    required this.builder,
  });

  final AsyncValue<List<T>> async;
  final String empty;
  final Future<void> Function() onRefresh;
  final List<Widget> Function(List<T> list) builder;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: ScreenInsets.symmetricScroll(context),
            children: list.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(empty)),
                    ),
                  ]
                : builder(list),
          ),
        );
      },
    );
  }
}
