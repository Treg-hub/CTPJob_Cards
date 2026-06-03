import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_work_record.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_issue_widgets.dart';
import 'fleet_add_cost_screen.dart';
import 'fleet_assets_screen.dart';
import 'fleet_issue_detail_screen.dart';
import 'fleet_issues_list_screen.dart';
import 'fleet_log_work_screen.dart';
import 'fleet_report_issue_screen.dart';
import 'fleet_reports_screen.dart';
import 'fleet_settings_screen.dart';
import 'fleet_work_records_list_screen.dart';

/// Fleet Maintenance home screen — entry point for the Fleet tab.
/// Sections shown depend on the user's fleet role.
class FleetHomeScreen extends ConsumerStatefulWidget {
  const FleetHomeScreen({super.key});

  @override
  ConsumerState<FleetHomeScreen> createState() => _FleetHomeScreenState();
}

class _FleetHomeScreenState extends ConsumerState<FleetHomeScreen> {
  final _service = FleetService();

  @override
  Widget build(BuildContext context) {
    final emp = currentEmployee;
    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;

    final isMechanic = role_utils.isFleetMechanic(emp);
    final isCostMgr = role_utils.isFleetCostManager(emp, settings);
    final isAdmin = role_utils.isFleetAdmin(emp);
    final isReporter = role_utils.isFleetReporter(emp, settings);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fleetSettingsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.directions_car_outlined,
                    color: kBrandOrange, size: 24),
                const SizedBox(width: 8),
                const Text('Fleet Maintenance',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            // ── OOS Alert banner ──────────────────────────────────────────
            StreamBuilder<List<FleetAsset>>(
              stream: _service.watchAssets(activeOnly: true),
              builder: (context, snapshot) {
                final assets = snapshot.data ?? [];
                final oos =
                    assets.where((a) => a.hasOpenOosIssue).toList();
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
                      Row(
                        children: [
                          const Icon(Icons.warning,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${oos.length} asset${oos.length == 1 ? '' : 's'} out of service',
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        oos.map((a) => a.name).join(', '),
                        style: const TextStyle(
                            color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ── Open Issues (mechanic + cost manager) ─────────────────────
            if (isMechanic || isCostMgr || isAdmin) ...[
              _SectionHeader(
                  title: 'Open Issues',
                  actionLabel: 'See All',
                  onAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              const FleetIssuesListScreen()))),
              StreamBuilder<List<FleetIssue>>(
                stream: _service.watchOpenIssues(limit: 5),
                builder: (context, snapshot) {
                  final issues = snapshot.data ?? [];
                  if (issues.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No open issues.',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return Column(
                    children: issues
                        .map((i) => FleetIssueTile(
                              issue: i,
                              onTap: () =>
                                  Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        FleetIssueDetailScreen(
                                            issueId: i.id!)),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // ── Recent Work (mechanic) ─────────────────────────────────────
            if (isMechanic || isAdmin) ...[
              _SectionHeader(
                  title: 'Recent Work',
                  actionLabel: 'All Records',
                  onAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              const FleetWorkRecordsListScreen()))),
              StreamBuilder<List<FleetWorkRecord>>(
                stream: _service.watchWorkRecords(
                    loggedByClockNo: emp?.clockNo, limit: 5),
                builder: (context, snapshot) {
                  final records = snapshot.data ?? [];
                  if (records.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No recent work records.',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return Column(
                    children: records
                        .map((r) => WorkRecordTile(record: r))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // ── My Reported Issues (reporters) ────────────────────────────
            if (isReporter && !isMechanic && !isAdmin) ...[
              _SectionHeader(title: 'My Reported Issues'),
              StreamBuilder<List<FleetIssue>>(
                stream: _service.watchIssues(
                    reportedByClockNo: emp?.clockNo, limit: 10),
                builder: (context, snapshot) {
                  final issues = snapshot.data ?? [];
                  if (issues.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'No issues reported yet. Tap below to report a problem.',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return Column(
                    children: issues
                        .map((i) => FleetIssueTile(
                              issue: i,
                              onTap: () =>
                                  Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        FleetIssueDetailScreen(
                                            issueId: i.id!)),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // ── Costs Pending (cost manager) ──────────────────────────────
            if (isCostMgr || isAdmin) ...[
              _SectionHeader(
                  title: 'Costs Pending',
                  actionLabel: 'Reports',
                  onAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              const FleetReportsScreen()))),
              StreamBuilder<List<FleetWorkRecord>>(
                stream: _service.watchWorkRecords(limit: 20),
                builder: (context, snapshot) {
                  final records = (snapshot.data ?? [])
                      .where((r) => !r.hasCostLines)
                      .take(5)
                      .toList();
                  if (records.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('All work records have been costed.',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return Column(
                    children: records
                        .map((r) => WorkRecordTile(record: r))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // ── Quick Actions ─────────────────────────────────────────────
            const Text('Quick Actions',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Reporter
                if (isReporter || isMechanic || isCostMgr || isAdmin)
                  _ActionChip(
                    label: 'Report Issue',
                    icon: Icons.report_problem_outlined,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetReportIssueScreen())),
                  ),
                // Mechanic
                if (isMechanic || isAdmin)
                  _ActionChip(
                    label: 'Log Work',
                    icon: Icons.build_outlined,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetLogWorkScreen())),
                  ),
                // Mechanic
                if (isMechanic || isAdmin)
                  _ActionChip(
                    label: 'Open Issues',
                    icon: Icons.assignment_late_outlined,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetIssuesListScreen())),
                  ),
                // Cost manager
                if (isCostMgr || isAdmin)
                  _ActionChip(
                    label: 'Add Cost',
                    icon: Icons.attach_money,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetAddCostScreen())),
                  ),
                // Cost manager
                if (isCostMgr || isAdmin)
                  _ActionChip(
                    label: 'Reports',
                    icon: Icons.bar_chart,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetReportsScreen())),
                  ),
                // Admin
                if (isAdmin)
                  _ActionChip(
                    label: 'Manage Assets',
                    icon: Icons.forklift,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetAssetsScreen())),
                  ),
                if (isAdmin)
                  _ActionChip(
                    label: 'Fleet Settings',
                    icon: Icons.settings_outlined,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const FleetSettingsScreen())),
                  ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0)),
              child: Text(actionLabel!,
                  style: const TextStyle(
                      color: kBrandOrange, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.label,
      required this.icon,
      required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: kBrandOrange),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
