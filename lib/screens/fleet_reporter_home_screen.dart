import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_daily_check_gate.dart';
import '../widgets/fleet_asset_grid.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_machine_action_sheet.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_reporter_widgets.dart';
import 'fleet_queued_screen.dart';
import 'fleet_report_wizard_screen.dart';
import 'fleet_reporter_issue_detail_screen.dart';

/// Reporter-only Fleet shell — machines, my reports, optional all-open view.
class FleetReporterHomeScreen extends ConsumerStatefulWidget {
  const FleetReporterHomeScreen({super.key});

  @override
  ConsumerState<FleetReporterHomeScreen> createState() =>
      _FleetReporterHomeScreenState();
}

class _FleetReporterHomeScreenState
    extends ConsumerState<FleetReporterHomeScreen> {
  final _service = FleetService();
  bool _showAllOpen = false;
  FleetDailyChecklistConfig _checklistConfig =
      FleetDailyChecklistConfig.defaults;

  @override
  void initState() {
    super.initState();
    _loadChecklistConfig();
  }

  Future<void> _loadChecklistConfig() async {
    final config = await _service.getDailyChecklistConfig();
    if (mounted) setState(() => _checklistConfig = config);
  }

  void _onMachineTap(FleetAsset asset) {
    showFleetMachineActionSheet(context, asset: asset);
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

    final emp = currentEmployee;
    final queuedFleet = SyncService().getQueuedFleetOperationCount();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openFleetReportWizard(context),
        icon: const Icon(Icons.report_problem_outlined),
        label: const Text('Report Problem'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Hyster / Fleet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (_checklistConfig.enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Machines',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                'Tap a machine for daily safety check or to report a problem.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).appColors.textMuted,
                ),
              ),
            ),
            StreamBuilder<List<FleetDailyCheck>>(
              stream: _service.watchDailyChecksForDate(),
              builder: (context, checkSnap) {
                final checks = checkSnap.data ?? [];
                final checkByAsset = {for (final c in checks) c.assetId: c};
                return FleetAssetGrid(
                  maxHeight: 200,
                  selectable: false,
                  selectedAsset: null,
                  onAssetSelected: _onMachineTap,
                  checkBadgeFor: (asset) {
                    if (asset.id == null) return FleetCheckBadge.none;
                    return fleetCheckBadgeForAsset(
                      asset: asset,
                      todayCheck: checkByAsset[asset.id],
                      checklistConfig: _checklistConfig,
                      settings: settings,
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('My reports')),
                ButtonSegment(value: true, label: Text('All open')),
              ],
              selected: {_showAllOpen},
              onSelectionChanged: (s) =>
                  setState(() => _showAllOpen = s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _showAllOpen
                ? _AllOpenList(service: _service)
                : _MyReportsList(service: _service, clockNo: emp?.clockNo),
          ),
        ],
      ),
    );
  }
}

class _MyReportsList extends StatelessWidget {
  const _MyReportsList({required this.service, required this.clockNo});
  final FleetService service;
  final String? clockNo;

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
                    'Tap a machine above or Report Problem when something goes wrong.',
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
            return _ReporterIssueCard(
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

class _AllOpenList extends StatelessWidget {
  const _AllOpenList({required this.service});
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
            return FleetIssueTile(
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

class _ReporterIssueCard extends StatelessWidget {
  const _ReporterIssueCard({required this.issue, required this.onTap});
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