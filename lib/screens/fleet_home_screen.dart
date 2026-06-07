import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_issue_widgets.dart';
import 'fleet_add_cost_screen.dart';
import 'fleet_assets_screen.dart' show FleetAssetsScreen, FleetAssetFormScreen;
import 'fleet_issue_detail_screen.dart';
import 'fleet_issues_list_screen.dart';
import 'fleet_log_work_screen.dart';
import 'fleet_report_issue_screen.dart';
import 'fleet_reports_screen.dart';
import 'fleet_settings_screen.dart';
import 'fleet_work_records_list_screen.dart';

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
  int _openIssuesCount = 0;
  StreamSubscription<List<FleetIssue>>? _issueCountSub;

  int _tabCount(bool isMechanic, bool isCostMgr, bool isAdmin) =>
      1 +
      (isMechanic || isAdmin ? 1 : 0) +
      (isCostMgr || isAdmin ? 1 : 0) +
      (isCostMgr || isAdmin ? 1 : 0) +
      (isAdmin ? 1 : 0) +
      (isAdmin ? 1 : 0);

  @override
  void initState() {
    super.initState();
    final settingsVal = ref.read(fleetSettingsProvider).asData?.value ?? FleetSettings.defaults;
    final emp = currentEmployee;
    final isMechanic = role_utils.isFleetMechanic(emp, settingsVal);
    final isCostMgr  = role_utils.isFleetCostManager(emp, settingsVal);
    final isAdmin    = role_utils.isFleetAdmin(emp);
    _tabController = TabController(length: _tabCount(isMechanic, isCostMgr, isAdmin), vsync: this)
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
    final emp      = currentEmployee;
    final settings = ref.watch(fleetSettingsProvider).asData?.value ?? FleetSettings.defaults;

    final isMechanic = role_utils.isFleetMechanic(emp, settings);
    final isCostMgr  = role_utils.isFleetCostManager(emp, settings);
    final isAdmin    = role_utils.isFleetAdmin(emp);
    final isReporter = role_utils.isFleetReporter(emp, settings);

    // ── Build role-based tab list ──────────────────────────────────────────
    final tabs = <Widget>[
      Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Issues'),
            if (_openIssuesCount > 0) ...[
              const SizedBox(width: 4),
              _FleetBadge(_openIssuesCount),
            ],
          ],
        ),
      ),
      if (isMechanic || isAdmin) const Tab(text: 'Work'),
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
      if (isMechanic || isAdmin) const FleetWorkRecordsListScreen(embedded: true),
      if (isCostMgr  || isAdmin) const FleetWorkRecordsListScreen(embedded: true, costsPendingOnly: true),
      if (isCostMgr  || isAdmin) const FleetReportsScreen(embedded: true),
      if (isAdmin) const FleetAssetsScreen(embedded: true),
      if (isAdmin) const FleetSettingsScreen(embedded: true),
    ];

    // Rebuild controller if role changed (e.g. settings loaded after init)
    if (_tabController.length != tabs.length) {
      _tabController.dispose();
      _tabController = TabController(length: tabs.length, vsync: this)
        ..addListener(() { if (mounted) setState(() {}); });
    }

    // Tab-aware FABs
    final int tabIdx = _tabController.index;
    Widget? fab;
    if (tabIdx == 0 && (isReporter || isMechanic || isAdmin)) {
      fab = FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FleetReportIssueScreen())),
        icon: const Icon(Icons.report_problem_outlined),
        label: const Text('Report Issue'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      );
    } else if ((isMechanic || isAdmin) && _tabIndexOf('Work', isMechanic, isCostMgr, isAdmin) == tabIdx) {
      fab = FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FleetLogWorkScreen())),
        icon: const Icon(Icons.build_outlined),
        label: const Text('Log Work'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      );
    } else if ((isCostMgr || isAdmin) && _tabIndexOf('Costs', isMechanic, isCostMgr, isAdmin) == tabIdx) {
      fab = FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FleetAddCostScreen())),
        icon: const Icon(Icons.attach_money),
        label: const Text('Add Cost'),
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

    return Scaffold(
      floatingActionButton: fab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

// ── Issues tab — OOS banner + issues list + reporter's own issues ────────────
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // OOS banner
        StreamBuilder<List<FleetAsset>>(
          stream: service.watchAssets(activeOnly: true),
          builder: (context, snapshot) {
            final oos = (snapshot.data ?? []).where((a) => a.hasOpenOosIssue).toList();
            if (oos.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
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
                    const Icon(Icons.warning, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Text('${oos.length} asset${oos.length == 1 ? '' : 's'} out of service',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(oos.map((a) => a.name).join(', '),
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            );
          },
        ),

        // Open issues (mechanic / cost mgr / admin)
        if (isMechanic || isCostMgr || isAdmin) ...[
          const FleetIssuesListScreen(embedded: true),
        ],

        // My reported issues (reporter only)
        if (isReporter && !isMechanic && !isAdmin) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('My Reported Issues', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          StreamBuilder<List<FleetIssue>>(
            stream: service.watchIssues(reportedByClockNo: emp?.clockNo, limit: 10),
            builder: (context, snapshot) {
              final issues = snapshot.data ?? [];
              if (issues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No issues reported yet. Tap "Report Issue" below.', style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: issues.map((i) => FleetIssueTile(
                  issue: i,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FleetIssueDetailScreen(issueId: i.id!),
                  )),
                )).toList(),
              );
            },
          ),
        ],
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
