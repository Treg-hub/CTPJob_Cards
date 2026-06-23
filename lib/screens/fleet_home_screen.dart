import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import 'fleet_add_cost_screen.dart';
import 'fleet_assets_screen.dart' show FleetAssetsScreen, FleetAssetFormScreen;
import 'fleet_issues_list_screen.dart';
import 'fleet_log_other_work_screen.dart';
import 'fleet_mechanic_home_screen.dart';
import 'fleet_queued_screen.dart';
import 'fleet_report_wizard_screen.dart';
import 'fleet_reporter_home_screen.dart';
import 'fleet_reports_screen.dart';
import 'fleet_settings_screen.dart';
import 'fleet_work_records_list_screen.dart';
import 'doc_viewer_screen.dart';
import '../models/doc_entry.dart';
import '../utils/fleet_guides.dart';
import '../services/sync_service.dart';

/// Fleet Maintenance home screen — tabbed entry point for the Fleet tab.
/// Tabs are role-filtered: Issues (all) | Work (mechanic+admin) |
/// Costs (cost manager+admin) | Reports (cost manager+admin) |
/// Assets (admin) | Settings (admin).
class FleetHomeScreen extends ConsumerStatefulWidget {
  const FleetHomeScreen({super.key});

  @override
  ConsumerState<FleetHomeScreen> createState() => _FleetHomeScreenState();
}

class _FleetHomeScreenState extends ConsumerState<FleetHomeScreen>
    with TickerProviderStateMixin {
  final _service = FleetService();

  late TabController _tabController;
  int _lastTabCount = 0;
  int _openIssuesCount = 0;
  StreamSubscription<List<FleetIssue>>? _issueCountSub;

  @override
  void initState() {
    super.initState();
    _lastTabCount = 1;
    _tabController = TabController(length: _lastTabCount, vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _issueCountSub = _service.watchOpenIssues(limit: 100).listen(
      (issues) { if (mounted) setState(() => _openIssuesCount = issues.length); },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _issueCountSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(fleetSettingsProvider);
    if (!settingsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final settings = settingsAsync.requireValue;
    if (!settings.fleetEnabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Fleet Maintenance is not enabled.\nAsk an admin to turn it on in Settings.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final emp      = currentEmployee;
    final isMechanic = role_utils.isFleetMechanic(emp, settings);
    final isCostMgr  = role_utils.isFleetCostManager(emp, settings);
    final isAdmin    = role_utils.isFleetAdmin(emp);
    final isReporter = role_utils.isFleetReporter(emp, settings);
    final mechanicUx = isMechanic && !isAdmin;
    final reporterOnly =
        isReporter && !isMechanic && !isCostMgr && !isAdmin;

    if (reporterOnly) {
      return const FleetReporterHomeScreen();
    }
    if (mechanicUx && !isCostMgr) {
      return const FleetMechanicHomeScreen();
    }

    // ── Build role-based tab list (admin / cost mgr / mixed roles) ───────
    final tabs = <Widget>[
      Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mechanicUx ? 'To Fix' : 'Issues'),
            if (_openIssuesCount > 0) ...[
              const SizedBox(width: 4),
              _FleetBadge(_openIssuesCount),
            ],
          ],
        ),
      ),
      if (isMechanic || isAdmin)
        Tab(text: mechanicUx ? 'History' : 'Work'),
      if (isCostMgr  || isAdmin) const Tab(text: 'Costs'),
      if (isCostMgr  || isAdmin) const Tab(text: 'Reports'),
      if (isAdmin) const Tab(text: 'Assets'),
      if (isAdmin) const Tab(text: 'Settings'),
    ];

    final tabViews = <Widget>[
      _IssuesTab(
        service: _service,
        emp: emp,
        isMechanic: isMechanic,
        isAdmin: isAdmin,
        isReporter: isReporter,
        isCostMgr: isCostMgr,
      ),
      if (isMechanic || isAdmin)
        FleetWorkRecordsListScreen(embedded: true, mechanicMode: mechanicUx),
      if (isCostMgr  || isAdmin)
        const FleetWorkRecordsListScreen(embedded: true, costManagerMode: true),
      if (isCostMgr  || isAdmin) const FleetReportsScreen(embedded: true),
      if (isAdmin) const FleetAssetsScreen(embedded: true),
      if (isAdmin) const FleetSettingsScreen(embedded: true),
    ];

    _syncTabController(tabs.length);

    // Tab-aware FABs
    final int tabIdx = _tabController.index;
    Widget? fab;
    if (tabIdx == 0 && role_utils.canReportFleetIssue(emp, settings)) {
      final reporterFab = isReporter && !isAdmin && !isCostMgr && !isMechanic;
      fab = FloatingActionButton.extended(
        onPressed: () => openFleetReportWizard(context),
        icon: const Icon(Icons.report_problem_outlined),
        label: Text(reporterFab ? 'Report Problem' : 'Report Issue'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      );
    } else if ((isMechanic || isAdmin) && _tabIndexOf('Work', isMechanic, isCostMgr, isAdmin) == tabIdx) {
      fab = FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FleetLogOtherWorkScreen())),
        icon: const Icon(Icons.build_outlined),
        label: Text(mechanicUx ? 'Log other work' : 'Log Work'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      );
    } else if ((isCostMgr || isAdmin) && _tabIndexOf('Costs', isMechanic, isCostMgr, isAdmin) == tabIdx) {
      final costMgrFab = isCostMgr && !isAdmin;
      fab = FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FleetAddCostScreen())),
        icon: const Icon(Icons.attach_money),
        label: Text(costMgrFab ? 'General cost' : 'Add Cost'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      );
    } else if (isAdmin && _tabIndexOf('Assets', isMechanic, isCostMgr, isAdmin) == tabIdx) {
      fab = FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FleetAssetFormScreen(service: FleetService(), asset: null),
        )),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      );
    }

    final fleetGuides = fleetGuidesFor(emp, settings);
    final queuedFleet = SyncService().getQueuedFleetOperationCount();

    return Scaffold(
      floatingActionButton: fab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (queuedFleet > 0)
            Material(
              color: kBrandOrange.withValues(alpha: 0.12),
              child: InkWell(
                onTap: () async {
                  unawaited(SyncService().processNow());
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FleetQueuedScreen(),
                  ));
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined,
                          color: kBrandOrange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$queuedFleet fleet item(s) waiting to sync — tap to view',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: kBrandOrange, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          if (fleetGuides.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openFleetGuides(context, fleetGuides),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(
                  fleetGuides.length == 1 ? 'Guide' : 'Guides',
                ),
              ),
            ),
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

  void _syncTabController(int tabCount) {
    if (_lastTabCount == tabCount) return;
    final oldIndex = _tabController.index;
    _tabController.dispose();
    _lastTabCount = tabCount;
    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: oldIndex.clamp(0, tabCount - 1),
    )..addListener(() { if (mounted) setState(() {}); });
  }

  void _openFleetGuides(BuildContext context, List<DocEntry> guides) {
    if (guides.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocViewerScreen(entry: guides.first),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Fleet guides',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ...guides.map(
              (guide) => ListTile(
                leading: Icon(guide.icon, color: kBrandOrange),
                title: Text(guide.title),
                subtitle: Text(guide.description),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocViewerScreen(entry: guide),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _tabIndexOf(String name, bool isMechanic, bool isCostMgr, bool isAdmin) {
    int i = 1;
    if (name == 'Work') return (isMechanic || isAdmin) ? i : -1;
    if (isMechanic || isAdmin) i++;
    if (name == 'Costs') return (isCostMgr || isAdmin) ? i : -1;
    if (isCostMgr || isAdmin) i++;
    if (name == 'Reports') return (isCostMgr || isAdmin) ? i : -1;
    if (isCostMgr || isAdmin) i++;
    if (name == 'Assets') return isAdmin ? i : -1;
    if (isAdmin) i++;
    if (name == 'Settings') return isAdmin ? i : -1;
    return -1;
  }
}

// ── Issues tab — OOS banner + shared open-issues list (all fleet roles) ───────
class _IssuesTab extends ConsumerWidget {
  const _IssuesTab({
    required this.service,
    required this.emp,
    required this.isMechanic,
    required this.isAdmin,
    required this.isReporter,
    required this.isCostMgr,
  });

  final FleetService service;
  final dynamic emp;
  final bool isMechanic, isAdmin, isReporter, isCostMgr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showIssuesList =
        isMechanic || isCostMgr || isAdmin || isReporter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: StreamBuilder<List<FleetAsset>>(
            stream: service.watchAssets(activeOnly: true),
            builder: (context, snapshot) {
              final assets = snapshot.data ?? [];
              final oos = assets.where((a) => a.hasOpenOosIssue).toList();
              final due = assets
                  .where((a) => a.serviceDue && !a.hasOpenOosIssue)
                  .toList();
              if (oos.isEmpty && due.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (oos.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.warning,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Text(
                                '${oos.length} asset${oos.length == 1 ? '' : 's'} out of service',
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 4),
                          Text(oos.map((a) => a.name).join(', '),
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    ),
                  if (due.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.amber.shade700),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.build_circle_outlined,
                                color: Colors.amber.shade800, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${due.length} Hyster${due.length == 1 ? '' : 's'} due for service',
                              style: TextStyle(
                                  color: Colors.amber.shade800,
                                  fontWeight: FontWeight.bold),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            due
                                .map((a) =>
                                    '${a.name} (${a.serviceDueReason})')
                                .join('\n'),
                            style: TextStyle(
                                color: Colors.amber.shade900, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (showIssuesList)
          Expanded(
            child: FleetIssuesListScreen(
              embedded: true,
              mechanicMode: isMechanic,
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tap "Report Issue" below to log a problem on a machine (forks, grab or BT).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Small orange badge for the Issues tab open-issues counter.
class _FleetBadge extends StatelessWidget {
  final int count;
  const _FleetBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: kBrandOrange, borderRadius: BorderRadius.circular(10)),
      child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
