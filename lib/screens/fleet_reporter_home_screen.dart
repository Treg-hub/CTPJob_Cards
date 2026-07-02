import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../utils/presence_gating.dart';
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_daily_check_gate.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_grid.dart';
import '../widgets/fleet_machine_action_sheet.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_reporter_widgets.dart';
import 'fleet_queued_screen.dart';
import 'fleet_reporter_issue_detail_screen.dart';

const _kReporterGuideDismissedPrefix = 'fleet_reporter_shell_guide_dismissed_';

/// Reporter-only Fleet shell — Machines tab + Reports tab.
class FleetReporterHomeScreen extends ConsumerStatefulWidget {
  const FleetReporterHomeScreen({
    super.key,
    this.initialTab = 0,
    this.standalone = false,
  });

  final int initialTab;
  final bool standalone;

  @override
  ConsumerState<FleetReporterHomeScreen> createState() =>
      _FleetReporterHomeScreenState();
}

class _FleetReporterHomeScreenState extends ConsumerState<FleetReporterHomeScreen>
    with TickerProviderStateMixin {
  final _service = FleetService();
  late TabController _tabController;
  bool _showAllOpen = false;
  bool _showGuide = true;
  FleetDailyChecklistConfig _checklistConfig =
      FleetDailyChecklistConfig.defaults;

  @override
  void initState() {
    super.initState();
    final startTab = widget.initialTab.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: startTab)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _loadChecklistConfig();
    _loadGuidePref();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _syncTabFromProvider(int tabIndex) {
    final tab = tabIndex.clamp(0, 1);
    if (_tabController.index != tab) {
      _tabController.animateTo(tab);
    }
  }

  Future<void> _loadChecklistConfig() async {
    final config = await _service.getDailyChecklistConfig();
    if (mounted) setState(() => _checklistConfig = config);
  }

  Future<void> _loadGuidePref() async {
    final emp = currentEmployee;
    if (emp == null) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('$_kReporterGuideDismissedPrefix${emp.clockNo}') ??
        false;
    if (mounted) setState(() => _showGuide = !dismissed);
  }

  Future<void> _dismissGuide() async {
    final emp = currentEmployee;
    if (emp != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
          '$_kReporterGuideDismissedPrefix${emp.clockNo}', true);
    }
    if (mounted) setState(() => _showGuide = false);
  }

  void _onMachineTap(FleetAsset asset) {
    showFleetMachineActionSheet(
      context,
      asset: asset,
      checklistEnabled: _checklistConfig.enabled,
    );
  }

  int _badgePriority(FleetCheckBadge badge) => switch (badge) {
        FleetCheckBadge.checkDue => 0,
        FleetCheckBadge.done => 1,
        FleetCheckBadge.none => 2,
      };

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(fleetReporterShellTabProvider, (_, next) {
      _syncTabFromProvider(next);
    });

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

    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseReporterFleetActions(
      emp: currentEmployee,
      settings: settings,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(
        title: 'Fleet Reporting',
        message: PresenceGating.offSiteReporterFleetMessage,
      );
    }

    final emp = currentEmployee;
    final queuedFleet = SyncService().getQueuedFleetOperationCount();

    final body = Column(
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
                        '$queuedFleet item(s) waiting to sync — tap to view',
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
        TabBar(
          controller: _tabController,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Machines'),
            Tab(text: 'Reports'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _MachinesTab(
                service: _service,
                checklistConfig: _checklistConfig,
                reporterDepartment: emp?.department,
                settings: settings,
                showGuide: _showGuide,
                onDismissGuide: _dismissGuide,
                onMachineTap: _onMachineTap,
                badgePriority: _badgePriority,
              ),
              _ReportsTab(
                service: _service,
                clockNo: emp?.clockNo,
                showAllOpen: _showAllOpen,
                onShowAllOpenChanged: (v) => setState(() => _showAllOpen = v),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.standalone) {
      return Scaffold(
        appBar: const FleetAppBar(title: 'Fleet — Machines'),
        body: body,
      );
    }
    return Scaffold(body: body);
  }
}

class _MachinesTab extends StatelessWidget {
  const _MachinesTab({
    required this.service,
    required this.checklistConfig,
    required this.reporterDepartment,
    required this.settings,
    required this.showGuide,
    required this.onDismissGuide,
    required this.onMachineTap,
    required this.badgePriority,
  });

  final FleetService service;
  final FleetDailyChecklistConfig checklistConfig;
  final String? reporterDepartment;
  final FleetSettings settings;
  final bool showGuide;
  final VoidCallback onDismissGuide;
  final void Function(FleetAsset asset) onMachineTap;
  final int Function(FleetCheckBadge badge) badgePriority;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final gridHeight = MediaQuery.sizeOf(context).height * 0.52;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGuide) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FleetReporterGuideBanner(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDismissGuide,
                    child: const Text('Got it — hide tip'),
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Tap a machine to report a problem or complete today\'s safety check.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<FleetDailyCheck>>(
            stream: service.watchDailyChecksForDate(),
            builder: (context, checkSnap) {
              final checks = checkSnap.data ?? [];
              final checkByAsset = {for (final c in checks) c.assetId: c};
              return FleetAssetGrid(
                maxHeight: gridHeight,
                selectable: false,
                selectedAsset: null,
                reporterDepartment: reporterDepartment,
                sortAssets: (assets) {
                  assets.sort((a, b) {
                    final badgeA = fleetCheckBadgeForAsset(
                      asset: a,
                      todayCheck: a.id != null ? checkByAsset[a.id] : null,
                      checklistConfig: checklistConfig,
                      settings: settings,
                    );
                    final badgeB = fleetCheckBadgeForAsset(
                      asset: b,
                      todayCheck: b.id != null ? checkByAsset[b.id] : null,
                      checklistConfig: checklistConfig,
                      settings: settings,
                    );
                    final cmp =
                        badgePriority(badgeA).compareTo(badgePriority(badgeB));
                    if (cmp != 0) return cmp;
                    return a.name.compareTo(b.name);
                  });
                  return assets;
                },
                onAssetSelected: onMachineTap,
                checkBadgeFor: (asset) {
                  if (!checklistConfig.enabled || asset.id == null) {
                    return FleetCheckBadge.none;
                  }
                  return fleetCheckBadgeForAsset(
                    asset: asset,
                    todayCheck: checkByAsset[asset.id],
                    checklistConfig: checklistConfig,
                    settings: settings,
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Check due / Done badges are reminders only. Use Report Problem on the home screen for a shortcut.',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({
    required this.service,
    required this.clockNo,
    required this.showAllOpen,
    required this.onShowAllOpenChanged,
  });

  final FleetService service;
  final String? clockNo;
  final bool showAllOpen;
  final ValueChanged<bool> onShowAllOpenChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('My reports')),
              ButtonSegment(value: true, label: Text('All open')),
            ],
            selected: {showAllOpen},
            onSelectionChanged: (s) => onShowAllOpenChanged(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: showAllOpen
              ? FleetReporterAllOpenList(service: service)
              : FleetReporterMyReportsList(
                  service: service,
                  clockNo: clockNo,
                  emptyHint:
                      'Tap Machines above or use Report Problem on the home screen.',
                ),
        ),
      ],
    );
  }
}

/// My reported issues — shared with dual-role mechanic shell tab.
class FleetReporterMyReportsList extends StatelessWidget {
  const FleetReporterMyReportsList({
    super.key,
    required this.service,
    required this.clockNo,
    this.emptyHint =
        'Tap a machine on the Machines tab or use Report Problem on the home screen.',
  });

  final FleetService service;
  final String? clockNo;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    if (clockNo == null) {
      return const Center(child: Text('Not signed in.'));
    }

    return StreamBuilder<List<FleetIssue>>(
      stream: service.watchIssues(reportedByClockNo: clockNo, limit: 50),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final issues = snapshot.data ?? [];
        if (issues.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forklift,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'You haven\'t reported any problems yet.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    emptyHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).appColors.textMuted),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: issues.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final issue = issues[index];
            return FleetReporterIssueCard(
              issue: issue,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    FleetReporterIssueDetailScreen(issueId: issue.id!),
              )),
            );
          },
        );
      },
    );
  }
}

/// All open floor issues — reporter-friendly labels.
class FleetReporterAllOpenList extends StatelessWidget {
  const FleetReporterAllOpenList({super.key, required this.service});
  final FleetService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FleetIssue>>(
      stream: service.watchOpenIssues(limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final issues = snapshot.data ?? [];
        if (issues.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No open problems. All clear!',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: issues.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final issue = issues[index];
            return FleetReporterIssueCard(
              issue: issue,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    FleetReporterIssueDetailScreen(issueId: issue.id!),
              )),
            );
          },
        );
      },
    );
  }
}

class FleetReporterIssueCard extends StatelessWidget {
  const FleetReporterIssueCard({
    super.key,
    required this.issue,
    required this.onTap,
  });

  final FleetIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Card(
      color: colors.cardSurface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: fleetSeverityColor(issue.severity),
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.assetName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      issue.description.length > 60
                          ? '${issue.description.substring(0, 60)}…'
                          : issue.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: colors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          reporterSeverityLabel(issue.severity),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: fleetSeverityColor(issue.severity),
                          ),
                        ),
                        Text(
                          mechanicIssueStatusLabel(issue.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kBrandOrange),
            ],
          ),
        ),
      ),
    );
  }
}