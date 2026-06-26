import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../utils/screen_insets.dart';
import 'fleet_log_other_work_screen.dart';
import 'fleet_mark_fixed_screen.dart';
import 'fleet_queued_screen.dart';
import 'fleet_work_records_list_screen.dart';

/// Mechanic-only Fleet shell — To Fix / In progress / History + service-due actions.
class FleetMechanicHomeScreen extends ConsumerStatefulWidget {
  const FleetMechanicHomeScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
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
    final tabIdx = _tabController.index;

    return Scaffold(
      floatingActionButton: tabIdx == 2
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FleetLogOtherWorkScreen(),
                ),
              ),
              icon: const Icon(Icons.build_outlined),
              label: const Text('Log other work'),
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
            )
          : null,
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
          _ServiceDueStrip(service: _service, onLogService: _openLogService),
          const FleetMechanicGuideBanner(),
          TabBar(
            controller: _tabController,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
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
              const Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: tabIdx == 2
                    ? ScreenInsets.scrollBottomInHomeShell(clearFab: true, extendedFab: true)
                    : 0,
              ),
              child: TabBarView(
              controller: _tabController,
              children: [
                _MechanicIssueList(
                  service: _service,
                  status: 'open',
                  emptyMessage: 'Nothing to fix right now.\nGood job!',
                  onTap: _openFix,
                ),
                _MechanicIssueList(
                  service: _service,
                  status: 'acknowledged',
                  emptyMessage: 'Nothing in progress.',
                  onTap: _openFix,
                  showFinishHint: true,
                ),
                const FleetWorkRecordsListScreen(
                  embedded: true,
                  mechanicMode: true,
                ),
              ],
            ),
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
  final _cardsKey = GlobalKey();

  void _scrollToCards() {
    final ctx = _cardsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

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
            FleetServiceDueBanner(count: due.length, onTap: _scrollToCards),
            Padding(
              key: _cardsKey,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
  });

  final FleetService service;
  final String status;
  final String emptyMessage;
  final void Function(FleetIssue issue) onTap;
  final bool showFinishHint;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FleetIssue>>(
      stream: service.watchIssues(status: status, limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final issues = snapshot.data ?? [];
        if (issues.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(emptyMessage, textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: issues.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final issue = issues[index];
            return FleetIssueTile(
              issue: issue,
              mechanicMode: true,
              onTap: () => onTap(issue),
              subtitleOverride: showFinishHint &&
                      issue.status == FleetIssueStatus.acknowledged
                  ? 'Tap to finish the repair'
                  : null,
            );
          },
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