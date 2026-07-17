import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_issue_sort.dart';
import '../utils/screen_insets.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_urgent_inbox_banner.dart';
import 'fleet_log_other_work_screen.dart';
import 'fleet_mark_fixed_screen.dart';
import 'fleet_queued_screen.dart';
import 'fleet_reporter_home_screen.dart';
import 'fleet_work_records_list_screen.dart';

/// Mechanic Fleet shell — To Fix / In progress / Log work / History (+ My reports when dual-role).
class FleetMechanicHomeScreen extends ConsumerStatefulWidget {
  const FleetMechanicHomeScreen({super.key, this.includeMyReportsTab = false});

  final bool includeMyReportsTab;

  @override
  ConsumerState<FleetMechanicHomeScreen> createState() =>
      _FleetMechanicHomeScreenState();
}

class _FleetMechanicHomeScreenState extends ConsumerState<FleetMechanicHomeScreen>
    with TickerProviderStateMixin {
  final _service = FleetService();
  late TabController _tabController;
  int _openCount = 0;
  StreamSubscription<List<FleetIssue>>? _countSub;

  int get _tabCount => widget.includeMyReportsTab ? 5 : 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _countSub = _service.watchIssues(status: 'open', limit: 100).listen(
      (issues) {
        if (mounted) setState(() => _openCount = issues.length);
      },
      onError: (_) {},
    );
  }

  @override
  void didUpdateWidget(FleetMechanicHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.includeMyReportsTab != widget.includeMyReportsTab) {
      final index = _tabController.index.clamp(0, _tabCount - 1);
      _tabController.dispose();
      _tabController = TabController(length: _tabCount, vsync: this, initialIndex: index)
        ..addListener(() {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _countSub?.cancel();
    super.dispose();
  }

  void _openFix(FleetIssue issue) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FleetMarkFixedScreen(
          preSelectedAssetId: issue.assetId,
          preSelectedAssetName: issue.assetName,
          linkedIssueId: issue.id!,
        ),
      ),
    );
  }

  void _openLogService(FleetAsset asset) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FleetLogOtherWorkScreen(
          preSelectedAssetId: asset.id,
          preSelectedWorkTypeLabel: 'routine',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(fleetSettingsProvider);
    if (!settingsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!settingsAsync.requireValue.fleetEnabled) {
      return const Center(child: Text('Fleet Maintenance is not enabled.'));
    }

    final queuedFleet = SyncService().getQueuedFleetOperationCount();
    final emp = currentEmployee;

    final tabViews = <Widget>[
      _MechanicIssueList(
        service: _service,
        status: 'open',
        emptyMessage: 'Nothing to fix right now.\nGood job!',
        onTap: _openFix,
        pinOos: true,
      ),
      _MechanicIssueList(
        service: _service,
        status: 'acknowledged',
        emptyMessage: 'Nothing in progress.',
        onTap: _openFix,
        showFinishHint: true,
      ),
      const FleetLogOtherWorkScreen(embedded: true),
      const FleetWorkRecordsListScreen(
        embedded: true,
        mechanicMode: true,
      ),
    ];

    final tabs = <Widget>[
      Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('To Fix'),
            if (_openCount > 0) ...[
              const SizedBox(width: 4),
              _CountBadge(_openCount),
            ],
          ],
        ),
      ),
      const Tab(text: 'In progress'),
      const Tab(text: 'Log work'),
      const Tab(text: 'History'),
    ];

    if (widget.includeMyReportsTab) {
      tabs.add(const Tab(text: 'My reports'));
      tabViews.add(FleetReporterMyReportsList(
        service: _service,
        clockNo: emp?.clockNo,
        emptyHint: 'Use the home screen Report Problem tile when you spot a fault.',
      ));
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (queuedFleet > 0)
            Material(
              color: kBrandOrange.withValues(alpha: 0.12),
              child: InkWell(
                onTap: () async {
                  await SyncService().processNow();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FleetQueuedScreen(),
                  ));
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined,
                          color: kBrandOrange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$queuedFleet item(s) waiting to sync',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const FleetUrgentInboxBanner(),
          _ServiceDueStrip(service: _service, onLogService: _openLogService),
          const FleetMechanicGuideBanner(),
          TabBar(
            controller: _tabController,
            // Centre the tab strip (scrollable default packs to the start).
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: tabs,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: tabViews,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceDueStrip extends StatefulWidget {
  const _ServiceDueStrip({
    required this.service,
    required this.onLogService,
  });

  final FleetService service;
  final void Function(FleetAsset asset) onLogService;

  @override
  State<_ServiceDueStrip> createState() => _ServiceDueStripState();
}

class _ServiceDueStripState extends State<_ServiceDueStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FleetAsset>>(
      stream: widget.service.watchAssets(activeOnly: true),
      builder: (context, snapshot) {
        final due = (snapshot.data ?? [])
            .where((a) => a.serviceDue && !a.hasOpenOosIssue)
            .toList();
        if (due.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FleetServiceDueBanner(
              count: due.length,
              onTap: () => setState(() => _expanded = !_expanded),
              expanded: _expanded,
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: due
                      .map((asset) => FleetServiceDueCard(
                            asset: asset,
                            onLogService: widget.onLogService,
                          ))
                      .toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MechanicIssueList extends StatelessWidget {
  const _MechanicIssueList({
    required this.service,
    required this.status,
    required this.emptyMessage,
    required this.onTap,
    this.showFinishHint = false,
    this.pinOos = false,
  });

  final FleetService service;
  final String status;
  final String emptyMessage;
  final void Function(FleetIssue issue) onTap;
  final bool showFinishHint;
  final bool pinOos;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FleetIssue>>(
      stream: service.watchIssues(status: status, limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snapshot.data ?? [];
        if (raw.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(emptyMessage, textAlign: TextAlign.center),
            ),
          );
        }

        final pinned = pinOos ? pinnedOpenOosIssues(raw) : <FleetIssue>[];
        final rest = pinOos
            ? openIssuesExcludingPinned(raw, pinned)
            : sortFleetIssuesByPriority(raw);

        return ListView(
          padding: ScreenInsets.listPadding(
            context,
            horizontal: 12,
            top: 12,
            inHomeShell: true,
          ),
          children: [
            if (pinned.isNotEmpty) ...[
              FleetPinnedOosSection(issues: pinned, onTap: onTap),
              const SizedBox(height: 8),
            ],
            ...rest.map((issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: FleetIssueTile(
                    issue: issue,
                    mechanicMode: true,
                    onTap: () => onTap(issue),
                    subtitleOverride: showFinishHint &&
                            issue.status == FleetIssueStatus.acknowledged
                        ? 'Tap to finish the repair'
                        : null,
                  ),
                )),
          ],
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: kBrandOrange,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}