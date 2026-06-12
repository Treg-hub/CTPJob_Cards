import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fleet_issue.dart';
import '../theme/app_theme.dart';
import 'fleet_issue_widgets.dart';

/// Read-only summary of a reported fault, shown at the top of the
/// work-logging form when the mechanic is fixing a report. The report
/// itself can never be edited — this card is reference material only.
class FleetIssueSummaryCard extends StatelessWidget {
  const FleetIssueSummaryCard({super.key, required this.issue});

  final FleetIssue issue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final fmt = DateFormat('d MMM yyyy HH:mm');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors?.cardSurface,
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem_outlined,
                  size: 16, color: colors?.textMuted),
              const SizedBox(width: 6),
              Text(
                'REPORTED FAULT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: colors?.textMuted,
                ),
              ),
              const Spacer(),
              FleetSeverityBadge(severity: issue.severity),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            issue.description,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          if (issue.parts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: issue.parts
                  .map((p) => Chip(
                        label: Text(p, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          if (issue.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: issue.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => _showPhoto(context, issue.photos[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      issue.photos[i],
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Reported by ${issue.reportedByName}'
            '${issue.createdAt != null ? ' · ${fmt.format(issue.createdAt!)}' : ''}',
            style: TextStyle(fontSize: 11, color: colors?.textMuted),
          ),
        ],
      ),
    );
  }

  void _showPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
