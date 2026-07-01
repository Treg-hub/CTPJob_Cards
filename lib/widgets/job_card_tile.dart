import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../theme/app_theme.dart';
import 'job_card_badges.dart';

class JobCardTile extends StatelessWidget {
  final JobCard job;
  final VoidCallback? onTap;
  final Widget? actions;
  final bool selected;

  const JobCardTile({
    super.key,
    required this.job,
    this.onTap,
    this.actions,
    this.selected = false,
  });

  static const double _compactStatusBreakpoint = 400;

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

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final appColors = Theme.of(context).appColors;
    final commentColor = appColors.statusOpen;
    final correctiveColor = appColors.statusCompleted;
    final priorityColor = JobCardColorUtils.priorityColor(context, job.priority);
    final lastComment = job.comments.isNotEmpty ? _lastEntry(job.comments) : '';
    final lastNote = job.notes.isNotEmpty ? _lastEntry(job.notes) : '';
    final lastCA = job.correctiveAction.isNotEmpty ? _lastEntry(job.correctiveAction) : '';
    final showStatusLabel = MediaQuery.sizeOf(context).width >= _compactStatusBreakpoint;

    final card = Card(
      elevation: 3,
      margin: EdgeInsets.zero,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (job.jobCardNumber != null) ...[
                        JobNumberBadge(number: job.jobCardNumber!),
                        const SizedBox(width: 6),
                      ],
                      PriorityBadge(priority: job.priority),
                      const SizedBox(width: 6),
                      JobTypeIcons(type: job.type),
                      const Spacer(),
                      JobStatusChip(
                        status: job.status,
                        showLabel: showStatusLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${job.department} > ${job.area} > ${job.machine} > ${job.part}',
                    style: TextStyle(color: muted, fontSize: 11.5, height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    job.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (lastComment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.comment_outlined, size: 13, color: commentColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastComment,
                            style: TextStyle(
                              fontSize: 12,
                              color: commentColor,
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
                          child: Icon(Icons.check_circle_outline, size: 13, color: correctiveColor),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastCA,
                            style: TextStyle(
                              fontSize: 12,
                              color: correctiveColor,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBrandOrange, width: 2),
            )
          : null,
      child: card,
    );
  }
}