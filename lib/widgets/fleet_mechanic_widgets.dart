import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../theme/app_theme.dart';

/// Plain-language status for mechanics (not admin jargon).
String mechanicIssueStatusLabel(FleetIssueStatus status) {
  switch (status) {
    case FleetIssueStatus.open:
      return 'Needs fixing';
    case FleetIssueStatus.acknowledged:
      return 'In progress';
    case FleetIssueStatus.resolved:
      return 'Fixed';
    case FleetIssueStatus.cancelled:
      return 'Cancelled';
  }
}

String mechanicIssueActionHint(FleetIssueStatus status) {
  switch (status) {
    case FleetIssueStatus.open:
      return 'Tap to view';
    case FleetIssueStatus.acknowledged:
      return 'Tap to finish';
    case FleetIssueStatus.resolved:
      return 'View fix';
    case FleetIssueStatus.cancelled:
      return 'View';
  }
}

class FleetMechanicGuideBanner extends StatelessWidget {
  const FleetMechanicGuideBanner({
    super.key,
    this.text =
        'Tap a problem to open it — it\'s logged as seen automatically. Tap Mark as Fixed when the repair is done.',
  });

  /// Banner for planned / non-issue work on the Log other work screen.
  const FleetMechanicGuideBanner.logOtherWork({super.key})
      : text =
            'For planned jobs (service, overhaul). Set when you started if the job '
            'took more than one day — finish time is recorded when you save.';

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.build_circle_outlined, color: kBrandOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent count banner — tap scrolls to [FleetServiceDueCard] list below.
class FleetServiceDueBanner extends StatelessWidget {
  const FleetServiceDueBanner({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.shade100,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  color: Colors.amber.shade900, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 machine due for service'
                      : '$count machines due for service',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
              Text(
                'View',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade800,
                ),
              ),
              Icon(Icons.keyboard_arrow_down,
                  color: Colors.amber.shade800, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-asset service-due card with Log service action.
class FleetServiceDueCard extends StatelessWidget {
  const FleetServiceDueCard({
    super.key,
    required this.asset,
    required this.onLogService,
  });

  final FleetAsset asset;
  final void Function(FleetAsset asset) onLogService;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.amber.withValues(alpha: 0.12),
      child: ListTile(
        dense: true,
        leading:
            Icon(Icons.build_circle_outlined, color: Colors.amber.shade800),
        title: Text(
          '${asset.name} — service due',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.amber.shade900,
          ),
        ),
        subtitle: Text(
          asset.serviceDueReason ?? 'Scheduled service',
          style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
        ),
        trailing: TextButton(
          onPressed: () => onLogService(asset),
          child: const Text('Log service'),
        ),
      ),
    );
  }
}

class FleetMechanicStatusBadge extends StatelessWidget {
  const FleetMechanicStatusBadge({super.key, required this.status});

  final FleetIssueStatus status;

  Color get _color {
    switch (status) {
      case FleetIssueStatus.open:
        return Colors.blue;
      case FleetIssueStatus.acknowledged:
        return Colors.orange;
      case FleetIssueStatus.resolved:
        return Colors.green;
      case FleetIssueStatus.cancelled:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        mechanicIssueStatusLabel(status),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}