import 'package:flutter/material.dart';

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
      return 'Tap to start';
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
        'Tap a problem → Start job when you begin → Finish the fix when done.',
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