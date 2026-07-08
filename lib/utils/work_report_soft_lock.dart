import 'package:flutter/material.dart';

import '../models/work_report_period.dart';

/// Soft-lock: warn when editing after Accounts may already have a PDF.
Future<bool> confirmWorkReportEditAfterPdf(
  BuildContext context, {
  required WorkReportPeriod? period,
}) async {
  if (period == null || !period.hasPdf) return true;
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
  return ok == true;
}
