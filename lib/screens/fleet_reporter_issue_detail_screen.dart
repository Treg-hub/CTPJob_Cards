import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fleet_issue.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_reporter_widgets.dart';

/// Read-only issue detail for reporter departments — status, report, and fix.
class FleetReporterIssueDetailScreen extends StatelessWidget {
  const FleetReporterIssueDetailScreen({super.key, required this.issueId});

  final String issueId;

  @override
  Widget build(BuildContext context) {
    final service = FleetService();
    final fmt = DateFormat('d MMM yyyy HH:mm');

    return Scaffold(
      appBar: const FleetAppBar(title: 'My Report'),
      body: StreamBuilder<FleetIssue?>(
        stream: service.watchIssue(issueId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final issue = snapshot.data;
          if (issue == null) {
            return const Center(child: Text('Report not found.'));
          }

          final colors = Theme.of(context).appColors;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                issue.assetName,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: fleetSeverityColor(issue.severity)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      reporterSeverityLabel(issue.severity),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fleetSeverityColor(issue.severity),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ReporterStatusChip(status: issue.status),
                ],
              ),
              const SizedBox(height: 20),

              Text(
                'Progress',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FleetIssueTimeline(issue: issue),
              const Divider(height: 32),

              Text(
                'Your report',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(issue.description, style: const TextStyle(fontSize: 14)),
              if (issue.createdAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Sent ${fmt.format(issue.createdAt!)}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
              if (issue.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: issue.photos
                      .map((url) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(url,
                                width: 80, height: 80, fit: BoxFit.cover),
                          ))
                      .toList(),
                ),
              ],

              if (issue.resolutionType == FleetIssueResolutionType.workRecord &&
                  issue.linkedWorkRecordId != null) ...[
                const Divider(height: 32),
                Text(
                  'The fix',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _ReporterFixCard(workRecordId: issue.linkedWorkRecordId!),
              ] else if (issue.status == FleetIssueStatus.open) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kBrandOrange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: kBrandOrange.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'The mechanic will see this under To Fix. '
                    'You\'ll see the fix here when it\'s done.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReporterStatusChip extends StatelessWidget {
  const _ReporterStatusChip({required this.status});
  final FleetIssueStatus status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (status) {
      case FleetIssueStatus.open:
        bg = Colors.blue;
      case FleetIssueStatus.acknowledged:
        bg = Colors.orange;
      case FleetIssueStatus.resolved:
        bg = Colors.green;
      case FleetIssueStatus.cancelled:
        bg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        mechanicIssueStatusLabel(status),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReporterFixCard extends StatelessWidget {
  const _ReporterFixCard({required this.workRecordId});
  final String workRecordId;

  @override
  Widget build(BuildContext context) {
    final service = FleetService();
    final fmt = DateFormat('d MMM yyyy');
    final colors = Theme.of(context).appColors;

    return FutureBuilder<FleetWorkRecord?>(
      future: service.getWorkRecord(workRecordId),
      builder: (context, snapshot) {
        final record = snapshot.data;
        if (record == null) {
          return Text(
            snapshot.connectionState == ConnectionState.waiting
                ? 'Loading the fix…'
                : 'Fix details not available.',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          color: Colors.green.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  record.workNumber,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  record.description,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
                StreamBuilder<List<FleetWorkPart>>(
                  stream: service.watchParts(workRecordId),
                  builder: (context, partsSnap) {
                    final parts = partsSnap.data ?? [];
                    if (parts.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Parts: ${parts.map((p) => p.partName).join(', ')}',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.engineering_outlined,
                        size: 14, color: colors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      record.loggedByName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.calendar_today_outlined,
                        size: 12, color: colors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      fmt.format(record.endDate),
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}