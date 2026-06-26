import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../theme/app_theme.dart';

class JobCardTile extends StatelessWidget {
  final JobCard job;
  final VoidCallback? onTap;
  final Widget? actions;

  const JobCardTile({
    super.key,
    required this.job,
    this.onTap,
    this.actions,
  });

  Color _priorityColor(BuildContext context, int priority) {
    final c = Theme.of(context).appColors;
    switch (priority) {
      case 1: return c.priority1;
      case 2: return c.priority2;
      case 3: return c.priority3;
      case 4: return c.priority4;
      case 5: return c.priority5;
      default: return Colors.grey;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final c = Theme.of(context).appColors;
    switch (status.toLowerCase()) {
      case 'open': return c.statusOpen;
      case 'inprogress':
      case 'in_progress':
      case 'in progress': return c.statusInProgress;
      case 'monitor':
      case 'monitoring':
      case 'completed': return c.statusCompleted;
      case 'closed':
      case 'cancelled': return c.statusCancelled;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(JobStatus status) {
    switch (status) {
      case JobStatus.open: return Icons.radio_button_unchecked;
      case JobStatus.inProgress: return Icons.autorenew;
      case JobStatus.monitor: return Icons.visibility;
      case JobStatus.closed: return Icons.check_circle;
    }
  }

  String _lastEntry(String text) {
    final parts = text.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts.last.trim();
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  List<Widget> _typeIcons(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    const size = 18.0;
    switch (job.type) {
      case JobType.mechanical:
        return [Icon(Icons.build, size: size, color: color)];
      case JobType.electrical:
        return [Icon(Icons.bolt, size: size, color: color)];
      case JobType.mechanicalElectrical:
        return [
          Icon(Icons.build, size: size, color: color),
          const SizedBox(width: 2),
          Icon(Icons.bolt, size: size, color: color),
        ];
      case JobType.maintenance:
        return [Icon(Icons.circle_outlined, size: size, color: color)];
      case JobType.building:
        return [Icon(Icons.home_repair_service, size: size, color: color)];
      case JobType.specialist:
        return [Icon(Icons.precision_manufacturing, size: size, color: color)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final statusColor = _statusColor(context, job.status.name);
    final priorityColor = _priorityColor(context, job.priority);
    final lastComment = job.comments.isNotEmpty ? _lastEntry(job.comments) : '';
    final lastNote = job.notes.isNotEmpty ? _lastEntry(job.notes) : '';
    final lastCA = job.correctiveAction.isNotEmpty ? _lastEntry(job.correctiveAction) : '';

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: priorityColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, actions != null ? 8 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Type + priority + status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ..._typeIcons(context),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: priorityColor.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'P${job.priority}',
                          style: TextStyle(
                            color: priorityColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_statusIcon(job.status), size: 13, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              job.status.displayName,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Location breadcrumb
                  Text(
                    '${job.department} > ${job.area} > ${job.machine} > ${job.part}',
                    style: TextStyle(color: muted, fontSize: 11.5, height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // JC# + description
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (job.jobCardNumber != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#${job.jobCardNumber}',
                            style: TextStyle(
                              color: onColor(Colors.blue),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          job.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (lastComment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.comment_outlined, size: 13, color: Colors.blue[400]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastComment,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade300,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (lastNote.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.edit_note, size: 13, color: muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastNote,
                            style: TextStyle(fontSize: 12, color: muted, fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (lastCA.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.check_circle_outline, size: 13, color: Colors.green[600]),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastCA,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.assignedNames?.isNotEmpty == true
                              ? job.assignedNames!.join(', ')
                              : 'Unassigned',
                          style: TextStyle(color: muted, fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (job.photos.isNotEmpty) ...[
                        Icon(Icons.photo_camera, size: 13, color: muted),
                        const SizedBox(width: 3),
                        Text('${job.photos.length}', style: TextStyle(color: muted, fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        job.createdAt != null ? _relativeTime(job.createdAt!) : '—',
                        style: const TextStyle(color: kBrandOrange, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (actions != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: actions,
            ),
        ],
      ),
    );
  }
}