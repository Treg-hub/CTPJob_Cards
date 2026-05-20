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

  String _lastEntry(String text) {
    final parts = text.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts.last.trim();
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final statusColor = _statusColor(context, job.status.name);
    final lastComment = job.comments.isNotEmpty ? _lastEntry(job.comments) : '';
    final lastNote = job.notes.isNotEmpty ? _lastEntry(job.notes) : '';
    final lastCA = job.correctiveAction.isNotEmpty ? _lastEntry(job.correctiveAction) : '';

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
              // Row 1: Priority + breadcrumb | Status + Type badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: RichText(
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
                            text: ' | ${job.department} > ${job.area} > ${job.machine} > ${job.part}',
                            style: TextStyle(color: muted, fontSize: 11.5, height: 1.2),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      job.status.displayName,
                      style: TextStyle(color: onColor(statusColor), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(20)),
                    child: Text(job.type.displayName, style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Row 2: JC# badge + Description
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (job.jobCardNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'JC #${job.jobCardNumber}',
                        style: TextStyle(color: onColor(Colors.blue), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      job.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onSurface, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                ],
              ),
              // Row 3: Comment preview
              if (lastComment.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.comment_outlined, size: 13, color: Colors.blue[400]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        lastComment,
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade300, fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              // Row 4: Note preview
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
              // Row 5: Corrective action preview (only when populated)
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
                        style: TextStyle(fontSize: 12, color: Colors.green[700], fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Row 6: Assigned names + Created timestamp
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.assignedNames?.isNotEmpty == true ? job.assignedNames!.join(', ') : 'Unassigned',
                      style: TextStyle(color: muted, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    job.createdAt != null ? _formatDateTime(job.createdAt!) : '—',
                    style: const TextStyle(color: kBrandOrange, fontSize: 12),
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
