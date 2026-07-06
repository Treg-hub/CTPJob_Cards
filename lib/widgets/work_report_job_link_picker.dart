import 'package:flutter/material.dart';

import '../models/job_card.dart';
import '../models/work_report_job_line.dart';
import '../theme/app_theme.dart';

/// Selectable job card for linking additional work (My Work + period lines).
class WorkReportJobLinkOption {
  const WorkReportJobLinkOption({
    required this.jobCardNumber,
    required this.machine,
    required this.description,
    required this.statusLabel,
  });

  final int jobCardNumber;
  final String machine;
  final String description;
  final String statusLabel;

  String get headline {
    final machinePart = machine.trim().isNotEmpty ? machine.trim() : 'No machine';
    return '#$jobCardNumber · $machinePart';
  }

  static List<WorkReportJobLinkOption> mergeSources({
    required List<JobCard> myWorkCards,
    required List<WorkReportJobLine> periodLines,
  }) {
    final byNumber = <int, WorkReportJobLinkOption>{};

    void add(int number, String machine, String description, String status) {
      if (number <= 0) return;
      byNumber[number] = WorkReportJobLinkOption(
        jobCardNumber: number,
        machine: machine,
        description: description,
        statusLabel: status,
      );
    }

    for (final job in myWorkCards) {
      final n = job.jobCardNumber;
      if (n == null) continue;
      add(
        n,
        job.machine,
        job.description,
        job.status.displayName,
      );
    }

    for (final line in periodLines) {
      add(
        line.jobCardNumber,
        line.jobMeta.machine,
        line.correctiveActionSnapshot.isNotEmpty
            ? line.correctiveActionSnapshot
            : line.billingSummary,
        line.orphan ? 'Removed from list' : 'In period',
      );
    }

    final sorted = byNumber.values.toList()
      ..sort((a, b) => b.jobCardNumber.compareTo(a.jobCardNumber));
    return sorted;
  }

  static String? labelForNumber(
    int? number,
    List<WorkReportJobLinkOption> options,
  ) {
    if (number == null) return null;
    for (final o in options) {
      if (o.jobCardNumber == number) return o.headline;
    }
    return '#$number';
  }
}

/// Result from the job-link picker. [changed] is false when the user dismissed
/// without choosing (back swipe / tap outside).
class WorkReportJobLinkPickResult {
  const WorkReportJobLinkPickResult({required this.changed, this.jobNumber});

  final bool changed;
  final int? jobNumber;
}

Future<WorkReportJobLinkPickResult?> showWorkReportJobLinkPicker(
  BuildContext context, {
  required List<WorkReportJobLinkOption> options,
  int? selected,
}) async {
  final raw = await showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final filtered = options.where((o) {
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return o.headline.toLowerCase().contains(q) ||
                o.description.toLowerCase().contains(q) ||
                o.statusLabel.toLowerCase().contains(q);
          }).toList();

          final scheme = Theme.of(ctx).colorScheme;
          final muted = Theme.of(ctx).appColors.textMuted;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (_, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Link to job card',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick from My Work or jobs already on this timesheet.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search machine or description',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    if (selected != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(ctx, const _ClearLink()),
                          icon: const Icon(Icons.link_off, size: 18),
                          label: const Text('Clear link'),
                        ),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                options.isEmpty
                                    ? 'No job cards in My Work or this period.\n'
                                        'Refresh job cards for period first.'
                                    : 'No matches for "$query".',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: muted),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final opt = filtered[i];
                                final isSelected = opt.jobCardNumber == selected;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  color: isSelected
                                      ? kBrandOrange.withValues(alpha: 0.12)
                                      : null,
                                  child: ListTile(
                                    title: Text(
                                      opt.headline,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${opt.statusLabel}'
                                      '${opt.description.trim().isNotEmpty ? ' · ${opt.description.trim()}' : ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: isSelected
                                        ? Icon(Icons.check_circle,
                                            color: scheme.primary)
                                        : null,
                                    onTap: () => Navigator.pop(
                                      ctx,
                                      WorkReportJobLinkPickResult(
                                        changed: true,
                                        jobNumber: opt.jobCardNumber,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );

  if (raw == null) return null;
  if (raw is _ClearLink) {
    return const WorkReportJobLinkPickResult(changed: true, jobNumber: null);
  }
  if (raw is WorkReportJobLinkPickResult) return raw;
  return null;
}

class _ClearLink {
  const _ClearLink();
}