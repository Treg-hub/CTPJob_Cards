import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fleet_issue.dart';
import '../theme/app_theme.dart';
import 'fleet_mechanic_widgets.dart';

/// Shared badge and tile widgets used across fleet issue screens.

/// Single source for severity colours (dot, badge, tile strip).
Color fleetSeverityColor(FleetIssueSeverity severity) {
  switch (severity) {
    case FleetIssueSeverity.outOfService: return Colors.red;
    case FleetIssueSeverity.high:         return Colors.orange;
    case FleetIssueSeverity.medium:       return Colors.yellow[700]!;
    case FleetIssueSeverity.low:          return Colors.green;
  }
}

class FleetSeverityDot extends StatelessWidget {
  const FleetSeverityDot({super.key, required this.severity});
  final FleetIssueSeverity severity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: fleetSeverityColor(severity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class FleetStatusBadge extends StatelessWidget {
  const FleetStatusBadge({super.key, required this.status});
  final FleetIssueStatus status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (status) {
      case FleetIssueStatus.open:         bg = Colors.blue; break;
      case FleetIssueStatus.acknowledged: bg = Colors.orange; break;
      case FleetIssueStatus.resolved:     bg = Colors.green; break;
      case FleetIssueStatus.cancelled:    bg = Colors.grey; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status.displayLabel,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }
}

class FleetSeverityBadge extends StatelessWidget {
  const FleetSeverityBadge({super.key, required this.severity});
  final FleetIssueSeverity severity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: fleetSeverityColor(severity),
          borderRadius: BorderRadius.circular(4)),
      child: Text(severity.displayLabel,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }
}

/// Reported → Started → Fixed stepper shown on the issue detail screen.
/// Cancelled issues show Reported → Cancelled instead.
class FleetIssueTimeline extends StatelessWidget {
  const FleetIssueTimeline({super.key, required this.issue});
  final FleetIssue issue;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy HH:mm');
    final cancelled = issue.status == FleetIssueStatus.cancelled;

    final steps = <_TimelineStep>[
      _TimelineStep(
        label: 'Reported',
        detail: [
          issue.reportedByName,
          if (issue.createdAt != null) fmt.format(issue.createdAt!),
        ].join(' · '),
        done: true,
      ),
      if (cancelled)
        _TimelineStep(
          label: 'Cancelled',
          detail: [
            if (issue.cancelledByName != null) issue.cancelledByName!,
            if (issue.cancelledAt != null) fmt.format(issue.cancelledAt!),
            if (issue.cancelReason != null) '— ${issue.cancelReason}',
          ].join(' · '),
          done: true,
          color: Colors.grey,
        )
      else ...[
        _TimelineStep(
          label: 'Started',
          detail: issue.acknowledgedAt != null
              ? [
                  if (issue.acknowledgedByName != null)
                    issue.acknowledgedByName!,
                  fmt.format(issue.acknowledgedAt!),
                ].join(' · ')
              : 'Waiting for the mechanic',
          done: issue.acknowledgedAt != null ||
              issue.status == FleetIssueStatus.resolved,
        ),
        _TimelineStep(
          label: 'Fixed',
          detail: issue.status == FleetIssueStatus.resolved
              ? [
                  if (issue.resolvedByName != null) issue.resolvedByName!,
                  if (issue.resolvedAt != null) fmt.format(issue.resolvedAt!),
                ].join(' · ')
              : 'Not fixed yet',
          done: issue.status == FleetIssueStatus.resolved,
        ),
      ],
    ];

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.label,
    required this.detail,
    required this.done,
    this.color,
  });
  final String label;
  final String detail;
  final bool done;
  final Color? color;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.isLast});
  final _TimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final dotColor =
        step.color ?? (step.done ? Colors.green : Colors.grey.shade400);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: step.done ? dotColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: dotColor, width: 2),
                ),
                child: step.done
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: step.done
                        ? dotColor.withValues(alpha: 0.5)
                        : Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: step.done ? null : colors?.textMuted,
                    ),
                  ),
                  if (step.detail.isNotEmpty)
                    Text(
                      step.detail,
                      style:
                          TextStyle(fontSize: 11, color: colors?.textMuted),
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

/// Issue row card used in list views and home screen.
/// Requires [onTap] to be wired externally (decouples from Navigator).
class FleetIssueTile extends StatelessWidget {
  const FleetIssueTile({
    super.key,
    required this.issue,
    required this.onTap,
    this.mechanicMode = false,
    this.subtitleOverride,
  });
  final FleetIssue issue;
  final VoidCallback onTap;
  final bool mechanicMode;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Card(
      color: colors?.cardSurface,
      clipBehavior: Clip.antiAlias,
      child: Container(
        // Severity strip — scannable from a distance, unlike text badges.
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: fleetSeverityColor(issue.severity),
              width: 4,
            ),
          ),
        ),
        child: ListTile(
        onTap: onTap,
        leading: FleetSeverityDot(severity: issue.severity),
        title: Text(
          issue.assetName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              issue.description.length > 80
                  ? '${issue.description.substring(0, 80)}…'
                  : issue.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors?.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (mechanicMode)
                  FleetMechanicStatusBadge(status: issue.status)
                else
                  FleetStatusBadge(status: issue.status),
                const SizedBox(width: 8),
                FleetSeverityBadge(severity: issue.severity),
                const Spacer(),
                if (subtitleOverride != null)
                  Text(
                    subtitleOverride!,
                    style: TextStyle(
                      color: kBrandOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (mechanicMode && issue.status.isOpen)
                  Text(
                    mechanicIssueActionHint(issue.status),
                    style: TextStyle(
                      color: kBrandOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    _formatAge(issue.createdAt),
                    style: TextStyle(color: colors?.textMuted, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  String _formatAge(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM').format(dt);
  }
}
