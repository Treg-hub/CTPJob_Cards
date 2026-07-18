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
import '../widgets/lurgi_period_banner.dart';

/// Open ink-count-period history for chemicals, recycling, and recovery.
///
/// Tabs follow the same pattern as View Jobs / My Work: **TabBar in the body**
/// (not AppBar.bottom) so [ThemeData.tabBarTheme] applies on the surface.
class LurgiPeriodHistoryScreen extends ConsumerStatefulWidget {
  const LurgiPeriodHistoryScreen({super.key});

  @override
  ConsumerState<LurgiPeriodHistoryScreen> createState() =>
      _LurgiPeriodHistoryScreenState();
}

class _LurgiPeriodHistoryScreenState
    extends ConsumerState<LurgiPeriodHistoryScreen>
    with SingleTickerProviderStateMixin {
  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM HH:mm');
  static const _tabLabels = ['Chemicals', 'Recycling', 'Recovery'];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    final settingsAsync = ref.watch(inkSettingsProvider);
    final periodFrom = settingsAsync.valueOrNull?.latestActiveCountDate;
    final chemAsync = ref.watch(lurgiPeriodChemicalUsageProvider);
    final recycAsync = ref.watch(lurgiPeriodRecyclingRunsProvider);
    final recovAsync = ref.watch(lurgiInkFactoryRecoveriesProvider);
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Period history')),
      // Match View Jobs: full-width centred tabs under the app bar (theme surface),
      // not TabBar as AppBar.bottom (orange bar breaks tabBarTheme contrast).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: false,
            tabs: [
              for (final label in _tabLabels) Tab(text: label),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: LurgiPeriodBanner(
              periodFrom: periodFrom,
              settingsLoading: settingsAsync.isLoading,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ListPane(
                  async: chemAsync,
                  empty: periodFrom == null && !settingsAsync.isLoading
                      ? 'No active count period — nothing to show.'
                      : 'No chemical entries in this period.',
                  onRefresh: () async {
                    ref.invalidate(lurgiPeriodChemicalUsageProvider);
                    ref.invalidate(inkSettingsProvider);
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
                  empty: periodFrom == null && !settingsAsync.isLoading
                      ? 'No active count period — nothing to show.'
                      : 'No recycling runs in this period.',
                  onRefresh: () async {
                    ref.invalidate(lurgiPeriodRecyclingRunsProvider);
                    ref.invalidate(inkSettingsProvider);
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
                  empty: periodFrom == null && !settingsAsync.isLoading
                      ? 'No active count period — nothing to show.'
                      : 'No Ink recovery posts in this period.',
                  onRefresh: () async {
                    ref.invalidate(lurgiInkFactoryRecoveriesProvider);
                    ref.invalidate(inkSettingsProvider);
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
