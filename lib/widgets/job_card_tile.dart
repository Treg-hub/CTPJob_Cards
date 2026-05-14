import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../theme/app_theme.dart';

class JobCardTile extends StatelessWidget {
  final JobCard job;
  final VoidCallback? onTap;

  const JobCardTile({super.key, required this.job, this.onTap});

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

  String _lastCommentPreview(String comments) {
    final parts = comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final last = parts.last;
    final lines = last.split('\n');
    return lines.length > 1 ? lines[1].trim() : last.trim();
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'P${job.priority}',
                      style: TextStyle(
                        color: _priorityColor(context, job.priority),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' | ${job.department} > ${job.area} > ${job.machine} > ${job.part} | ${job.operator}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
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
                        'JC #${job.jobCardNumber}',
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (job.comments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _lastCommentPreview(job.comments),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade300,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (job.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    job.notes.split('\n').last.trim(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(context, job.status.name),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.status.displayName,
                      style: TextStyle(
                        color: onColor(_statusColor(context, job.status.name)),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.type.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          job.assignedNames?.join(', ') ?? 'Unassigned',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          job.lastUpdatedAt != null
                              ? _formatDateTime(job.lastUpdatedAt!)
                              : '—',
                          style: const TextStyle(color: kBrandOrange, fontSize: 12),
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      if (job.comments.isNotEmpty)
                        Icon(Icons.comment_outlined, size: 16, color: Colors.blue[400]),
                      if (job.notes.isNotEmpty)
                        Icon(Icons.build_outlined, size: 16, color: Colors.orange[400]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
