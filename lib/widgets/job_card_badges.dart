import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../theme/app_theme.dart';

/// Shared color/icon lookups for job card priority and status badges.
class JobCardColorUtils {
  JobCardColorUtils._();

  static Color priorityColor(BuildContext context, int priority) {
    final c = Theme.of(context).appColors;
    switch (priority) {
      case 1:
        return c.priority1;
      case 2:
        return c.priority2;
      case 3:
        return c.priority3;
      case 4:
        return c.priority4;
      case 5:
        return c.priority5;
      default:
        return Colors.grey;
    }
  }

  static Color statusColor(BuildContext context, JobStatus status) {
    return statusColorFromName(context, status.name);
  }

  static Color statusColorFromName(BuildContext context, String status) {
    final c = Theme.of(context).appColors;
    switch (status.toLowerCase()) {
      case 'open':
        return c.statusOpen;
      case 'inprogress':
      case 'in_progress':
      case 'in progress':
        return c.statusInProgress;
      case 'monitor':
      case 'monitoring':
      case 'completed':
        return c.statusCompleted;
      case 'closed':
      case 'cancelled':
        return c.statusCancelled;
      default:
        return Colors.grey;
    }
  }

  static IconData statusIcon(JobStatus status) {
    switch (status) {
      case JobStatus.open:
        return Icons.radio_button_unchecked;
      case JobStatus.inProgress:
        return Icons.autorenew;
      case JobStatus.monitor:
        return Icons.visibility;
      case JobStatus.closed:
        return Icons.check_circle;
    }
  }
}

enum PriorityBadgeStyle { outlined, filled }

class JobNumberBadge extends StatelessWidget {
  const JobNumberBadge({super.key, required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    const bg = kBrandOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$number',
        style: TextStyle(
          color: onColor(bg),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({
    super.key,
    required this.priority,
    this.style = PriorityBadgeStyle.outlined,
  });

  final int priority;
  final PriorityBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    final color = JobCardColorUtils.priorityColor(context, priority);
    final label = 'P$priority';

    if (style == PriorityBadgeStyle.filled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onColor(color),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class JobStatusChip extends StatelessWidget {
  const JobStatusChip({
    super.key,
    required this.status,
    this.showLabel = true,
    this.style = PriorityBadgeStyle.outlined,
  });

  final JobStatus status;
  final bool showLabel;
  final PriorityBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    final color = JobCardColorUtils.statusColor(context, status);
    final icon = JobCardColorUtils.statusIcon(status);
    final label = status.displayName;

    Widget chip;
    if (style == PriorityBadgeStyle.filled) {
      chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onColor(color),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    } else {
      chip = Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 8 : 6,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (!showLabel && style == PriorityBadgeStyle.outlined) {
      return Tooltip(message: label, child: chip);
    }
    return chip;
  }
}

class JobTypeIcons extends StatelessWidget {
  const JobTypeIcons({super.key, required this.type, this.size = 18});

  final JobType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final icons = <Widget>[];
    switch (type) {
      case JobType.mechanical:
        icons.add(Icon(Icons.build, size: size, color: color));
      case JobType.electrical:
        icons.add(Icon(Icons.bolt, size: size, color: color));
      case JobType.mechanicalElectrical:
        icons.addAll([
          Icon(Icons.build, size: size, color: color),
          const SizedBox(width: 2),
          Icon(Icons.bolt, size: size, color: color),
        ]);
      case JobType.maintenance:
        icons.add(Icon(Icons.circle_outlined, size: size, color: color));
      case JobType.building:
        icons.add(Icon(Icons.home_repair_service, size: size, color: color));
      case JobType.specialist:
        icons.add(Icon(Icons.precision_manufacturing, size: size, color: color));
      case JobType.postPressSpecialist:
        icons.add(Icon(Icons.content_cut, size: size, color: color));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: icons);
  }
}