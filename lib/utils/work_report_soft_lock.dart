import 'package:flutter/material.dart';

import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import 'work_report_period_utils.dart';

/// Confirm edits that need extra care: past periods and/or post-PDF changes.
///
/// Past-period edits always prompt a warning (and callers should audit).
/// PDF soft-lock prompts when Accounts may already have a shared PDF.
Future<bool> confirmWorkReportEdit(
  BuildContext context, {
  required WorkReportPeriod? period,
  required String periodKey,
  WorkReportSettings? settings,
}) async {
  final s = settings ?? WorkReportSettings.defaults;
  final isPast = WorkReportPeriodUtils.isPastPeriod(
    periodKey,
    periodMode: s.defaultPeriodMode,
    periodStartDay: s.periodStartDay,
  );

  if (isPast) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editing a past week'),
        content: Text(
          'You are changing a previous timesheet period '
          '(${WorkReportPeriodUtils.periodLabel(periodKey)}).\n\n'
          'This will be logged in the audit trail. Continue only if the change '
          'is intentional (e.g. correction for Accounts).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Edit past week'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }

  if (!context.mounted) return false;

  if (period != null && period.hasPdf) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF already generated'),
        content: Text(
          'A PDF (v${period.pdfVersion}) was shared for this period. '
          'Editing may not match what Accounts received. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Edit anyway'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }

  return true;
}

/// @Deprecated Use [confirmWorkReportEdit] with periodKey.
Future<bool> confirmWorkReportEditAfterPdf(
  BuildContext context, {
  required WorkReportPeriod? period,
}) async {
  if (period == null || !period.hasPdf) return true;
  return confirmWorkReportEdit(
    context,
    period: period,
    periodKey: period.periodKey,
  );
}
