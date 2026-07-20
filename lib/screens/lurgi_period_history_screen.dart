import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/ink_transaction.dart';
import '../models/lurgi_chemical_usage.dart';
import '../models/lurgi_daily_round.dart';
import '../models/lurgi_recycling_run.dart';
import '../providers/ink_provider.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/lurgi_period_banner.dart';

/// Open ink-count-period history: chemicals, recycling, recovery, morning.
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
  static const _tabLabels = ['Chemicals', 'Recycling', 'Recovery', 'Morning'];

  late final TabController _tabController;

  // Paginated state
  final List<LurgiChemicalUsage> _chem = [];
  final List<LurgiRecyclingRun> _recyc = [];
  final List<InkTransaction> _recov = [];
  final List<LurgiDailyRound> _morning = [];
  DocumentSnapshot? _chemCursor;
  DocumentSnapshot? _recycCursor;
  DocumentSnapshot? _recovCursor;
  bool _chemHasMore = true;
  bool _recycHasMore = true;
  bool _recovHasMore = true;
  bool _chemLoading = false;
  bool _recycLoading = false;
  bool _recovLoading = false;
  bool _morningLoading = false;
  String? _loadedForPeriodKey;

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

  Future<void> _ensureLoaded(DateTime? periodFrom) async {
    if (periodFrom == null) return;
    final key = periodFrom.toIso8601String();
    if (_loadedForPeriodKey == key) return;
    _loadedForPeriodKey = key;
    _chem.clear();
    _recyc.clear();
    _recov.clear();
    _morning.clear();
    _chemCursor = null;
    _recycCursor = null;
    _recovCursor = null;
    _chemHasMore = true;
    _recycHasMore = true;
    _recovHasMore = true;
    await Future.wait([
      _loadMoreChem(periodFrom),
      _loadMoreRecyc(periodFrom),
      _loadMoreRecov(periodFrom),
      _loadMorning(periodFrom),
    ]);
  }

  Future<void> _loadMoreChem(DateTime periodFrom) async {
    if (_chemLoading || !_chemHasMore) return;
    setState(() => _chemLoading = true);
    try {
      final page = await ref.read(lurgiServiceProvider).fetchChemicalUsagePage(
            periodFromExclusive: periodFrom,
            startAfter: _chemCursor,
          );
      if (!mounted) return;
      setState(() {
        _chem.addAll(page.rows);
        _chemCursor = page.lastDoc;
        _chemHasMore = page.rows.length >= 40 && page.lastDoc != null;
        _chemLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chemLoading = false);
    }
  }

  Future<void> _loadMoreRecyc(DateTime periodFrom) async {
    if (_recycLoading || !_recycHasMore) return;
    setState(() => _recycLoading = true);
    try {
      final page = await ref.read(lurgiServiceProvider).fetchRecyclingRunsPage(
            periodFromExclusive: periodFrom,
            startAfter: _recycCursor,
          );
      if (!mounted) return;
      setState(() {
        _recyc.addAll(page.rows);
        _recycCursor = page.lastDoc;
        _recycHasMore = page.rows.length >= 40 && page.lastDoc != null;
        _recycLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _recycLoading = false);
    }
  }

  Future<void> _loadMoreRecov(DateTime periodFrom) async {
    if (_recovLoading || !_recovHasMore) return;
    setState(() => _recovLoading = true);
    try {
      final page =
          await ref.read(lurgiServiceProvider).fetchInkFactoryRecoveriesPage(
                periodFromExclusive: periodFrom,
                startAfter: _recovCursor,
              );
      if (!mounted) return;
      setState(() {
        _recov.addAll(page.rows);
        _recovCursor = page.lastDoc;
        _recovHasMore = page.rows.length >= 40 && page.lastDoc != null;
        _recovLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _recovLoading = false);
    }
  }

  Future<void> _loadMorning(DateTime periodFrom) async {
    setState(() => _morningLoading = true);
    try {
      final rows = await ref
          .read(lurgiServiceProvider)
          .fetchRoundsForOpenPeriod(periodFromExclusive: periodFrom);
      if (!mounted) return;
      setState(() {
        _morning
          ..clear()
          ..addAll(rows);
        _morningLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _morningLoading = false);
    }
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
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    if (periodFrom != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureLoaded(periodFrom);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Period history')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
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
            child: periodFrom == null && !settingsAsync.isLoading
                ? const Center(
                    child: Text('No active count period — nothing to show.'),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _pagedList(
                        loading: _chemLoading && _chem.isEmpty,
                        empty: 'No chemical entries in this period.',
                        hasMore: _chemHasMore,
                        onLoadMore: () => _loadMoreChem(periodFrom!),
                        loadingMore: _chemLoading,
                        children: [
                          for (final e in _chem)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  '${_qty.format(e.totalKg)} kg · ${_df.format(e.recordedAt)}'
                                  '${e.voidRequested ? ' · void req' : ''}',
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
                                  style:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                        ],
                      ),
                      _pagedList(
                        loading: _recycLoading && _recyc.isEmpty,
                        empty: 'No recycling runs in this period.',
                        hasMore: _recycHasMore,
                        onLoadMore: () => _loadMoreRecyc(periodFrom!),
                        loadingMore: _recycLoading,
                        children: [
                          for (final r in _recyc)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(Icons.recycling_outlined,
                                    color: appColors.lurgiAccent),
                                title: Text(
                                  '${_qty.format(r.litresRecycled)} L · ${_df.format(r.startAt)}'
                                  '${r.voidRequested ? ' · void req' : ''}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  'Dirty ${_qty.format(r.dirtyToloulLevelLitres)} L'
                                  '${r.machineCleaned ? ' · cleaned' : ''}'
                                  '${r.actorName.isNotEmpty ? ' · ${r.actorName}' : ''}',
                                  style:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                        ],
                      ),
                      _pagedList(
                        loading: _recovLoading && _recov.isEmpty,
                        empty: 'No Ink recovery posts in this period.',
                        hasMore: _recovHasMore,
                        onLoadMore: () => _loadMoreRecov(periodFrom!),
                        loadingMore: _recovLoading,
                        children: [
                          for (final t in _recov)
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
                                  style:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                        ],
                      ),
                      _morningPane(scheme, appColors),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _morningPane(ColorScheme scheme, AppColors appColors) {
    if (_morningLoading && _morning.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_morning.isEmpty) {
      return const Center(child: Text('No morning rounds in this period.'));
    }
    return ListView(
      padding: ScreenInsets.symmetricScroll(context),
      children: [
        for (final r in _morning)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                r.morningComplete ? Icons.check_circle : Icons.pending_outlined,
                color: r.morningComplete
                    ? appColors.statusCompleted
                    : appColors.lurgiAccent,
              ),
              title: Text(
                '${r.dateKey} · ${r.completedSectionCount}/${LurgiDailyRound.totalSections}'
                '${r.morningComplete ? ' complete' : ''}'
                '${(r.meterSpanDays ?? 0) > 1 ? ' · multi-day gap' : ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              subtitle: Text(
                [
                  if (r.utilitiesComplete) 'utilities',
                  if (r.waterComplete) 'water',
                  if (r.airComplete) 'air',
                  if (r.geyserComplete) 'geyser',
                  if (r.tanksComplete) 'tanks',
                  if (r.chemicalsNoneToday) 'chem none',
                  if (r.recyclingNoneToday) 'recycle none',
                  if (r.actorName != null && r.actorName!.isNotEmpty)
                    r.actorName!,
                ].join(' · '),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pagedList({
    required bool loading,
    required String empty,
    required bool hasMore,
    required VoidCallback onLoadMore,
    required bool loadingMore,
    required List<Widget> children,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: ScreenInsets.symmetricScroll(context),
      children: [
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(empty)),
          )
        else
          ...children,
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: onLoadMore,
                      child: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}
