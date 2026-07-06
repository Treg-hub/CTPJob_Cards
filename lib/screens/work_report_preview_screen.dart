import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/work_report_period.dart';
import '../widgets/ctp_app_bar.dart';

/// In-app PDF preview before the worker shares to Accounts.
class WorkReportPreviewScreen extends StatelessWidget {
  const WorkReportPreviewScreen({
    super.key,
    required this.period,
    required this.pdfBytes,
    required this.onShare,
  });

  final WorkReportPeriod period;
  final Uint8List pdfBytes;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CtpAppBar(title: 'Preview timesheet PDF'),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfFileName:
            'timesheet_${period.clockNo}_${period.periodKey}.pdf',
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () async {
              await onShare();
              if (context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share PDF'),
          ),
        ),
      ),
    );
  }
}