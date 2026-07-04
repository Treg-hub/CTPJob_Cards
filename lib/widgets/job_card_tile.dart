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

  static const double _tileRadius = 10;
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

  Widget _activityRow({
    required IconData icon,
    required Color color,
    required String text,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontStyle: FontStyle.italic,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final onSurface = scheme.onSurface;
    final appColors = Theme.of(context).appColors;
    final commentColor = appColors.statusOpen;
    final correctiveColor = appColors.statusCompleted;
    final priorityColor = JobCardColorUtils.priorityColor(context, job.priority);
    final lastComment = job.comments.isNotEmpty ? _lastEntry(job.comments) : '';
    final lastNote = job.notes.isNotEmpty ? _lastEntry(job.notes) : '';
    final lastCA =
        job.correctiveAction.isNotEmpty ? _lastEntry(job.correctiveAction) : '';
    final showStatusLabel = MediaQuery.sizeOf(context).width >= _compactStatusBreakpoint;
    final hasActivity =
        lastComment.isNotEmpty || lastNote.isNotEmpty || lastCA.isNotEmpty;

    final card = Material(
      color: appColors.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_tileRadius),
        side: BorderSide(
          color: priorityColor.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: priorityColor),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: onTap,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            10,
                            10,
                            actions != null ? 6 : 10,
                          ),
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
                              const SizedBox(height: 4),
                              Text(
                                '${job.department} > ${job.area} > ${job.machine} > ${job.part}',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                job.description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.25,
                                ),
                              ),
                              if (hasActivity) ...[
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: scheme.outlineVariant
                                          .withValues(alpha: 0.6),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (lastComment.isNotEmpty)
                                        _activityRow(
                                          icon: Icons.comment_outlined,
                                          color: commentColor,
                                          text: lastComment,
                                        ),
                                      if (lastNote.isNotEmpty) ...[
                                        if (lastComment.isNotEmpty)
                                          const SizedBox(height: 4),
                                        _activityRow(
                                          icon: Icons.edit_note,
                                          color: muted,
                                          text: lastNote,
                                        ),
                                      ],
                                      if (lastCA.isNotEmpty) ...[
                                        if (lastComment.isNotEmpty ||
                                            lastNote.isNotEmpty)
                                          const SizedBox(height: 4),
                                        _activityRow(
                                          icon: Icons.check_circle_outline,
                                          color: correctiveColor,
                                          text: lastCA,
                                          maxLines: 2,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      job.assignedNames?.isNotEmpty == true
                                          ? job.assignedNames!.join(', ')
                                          : 'Unassigned',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (job.photos.isNotEmpty) ...[
                                    Icon(Icons.photo_camera,
                                        size: 13, color: muted),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${job.photos.length}',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    job.createdAt != null
                                        ? _relativeTime(job.createdAt!)
                                        : '—',
                                    style: const TextStyle(
                                      color: kBrandOrange,
                                      fontSize: 12,
                                    ),
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
                              top: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          child: actions,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(_tileRadius),
              border: Border.all(color: kBrandOrange, width: 2),
            )
          : null,
      child: card,
    );
  }
}