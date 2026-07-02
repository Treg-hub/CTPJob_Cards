import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_tips_provider.dart';
import '../theme/app_theme.dart';
import 'fleet_issue_widgets.dart';

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

class FleetMechanicGuideBanner extends ConsumerWidget {
  const FleetMechanicGuideBanner({
    super.key,
    this.text =
        'Out-of-service problems are pinned at the top. Tap a fault → Save progress if you\'re starting a multi-day job, or Mark as Fixed when done. Planned jobs: Log work tab.',
  });

  /// Banner for planned / non-issue work on the Log other work screen.
  const FleetMechanicGuideBanner.logOtherWork({super.key})
      : text =
            'For planned jobs (service, overhaul). Set when you started if the job '
            'took more than one day — finish time is recorded when you save.';

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(fleetTipsVisibleProvider);
    if (!visible) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
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
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Hide tips (Settings > Preferences to bring back)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              ref.read(fleetTipsVisibleProvider.notifier).setVisible(false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tips hidden — turn back on in Settings > Preferences'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Prominent count banner — tap scrolls to [FleetServiceDueCard] list below.
class FleetPinnedOosSection extends StatelessWidget {
  const FleetPinnedOosSection({
    super.key,
    required this.issues,
    required this.onTap,
  });

  final List<FleetIssue> issues;
  final void Function(FleetIssue issue) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issues.length == 1
                      ? 'Out of service — fix first'
                      : '${issues.length} out of service — fix first',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ...issues.map(
          (issue) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: FleetIssueTile(
              issue: issue,
              mechanicMode: true,
              onTap: () => onTap(issue),
              subtitleOverride: 'Out of service',
            ),
          ),
        ),
      ],
    );
  }
}

class FleetServiceDueBanner extends StatelessWidget {
  const FleetServiceDueBanner({
    super.key,
    required this.count,
    required this.onTap,
    this.expanded = false,
  });

  final int count;
  final VoidCallback onTap;
  final bool expanded;

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
                expanded ? 'Hide' : 'View',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade800,
                ),
              ),
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.amber.shade800,
                size: 20,
              ),
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