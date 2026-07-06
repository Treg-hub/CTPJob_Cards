import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/work_report_additional_line.dart';
import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../utils/work_report_period_utils.dart';

class WorkReportPdfExporter {
  static final _hours = NumberFormat('#,##0.##');
  static final _fileDate = DateFormat('yyyy-MM-dd_HHmm');

  static Future<File> generateAndShare({
    required WorkReportPeriod period,
    required List<WorkReportJobLine> jobLines,
    required List<WorkReportAdditionalLine> additionalLines,
  }) async {
    final doc = pw.Document();
    final periodLabel = WorkReportPeriodUtils.periodLabel(period.periodKey);
    final fromStr = DateFormat('d MMM yyyy').format(period.periodStart);
    final toStr = DateFormat('d MMM yyyy').format(period.periodEnd);
    final generated = DateFormat('d MMM yyyy HH:mm').format(DateTime.now());

    final sortedJobs = [...jobLines]
      ..sort((a, b) => a.jobCardNumber.compareTo(b.jobCardNumber));
    final sortedAdd = [...additionalLines]
      ..sort((a, b) => a.workDate.compareTo(b.workDate));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'CTP — My Timesheet',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(periodLabel,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text('$fromStr – $toStr', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.Text('Name: ${period.employeeName}'),
          pw.Text('Clock: ${period.clockNo}'),
          pw.Text('Department: ${period.department}'),
          pw.Text('Position: ${period.position}'),
          pw.SizedBox(height: 16),
          pw.Text('Job card work',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (sortedJobs.isEmpty)
            pw.Text('No job card lines.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Job #',
                'Type',
                'Location',
                'Hours',
                'Work done',
                'Billing summary',
              ],
              data: [
                for (final line in sortedJobs)
                  [
                    line.jobCardNumber > 0 ? '#${line.jobCardNumber}' : '—',
                    line.jobMeta.type,
                    _truncate(line.jobMeta.locationLabel, 40),
                    _hours.format(line.hours),
                    _truncate(line.correctiveActionSnapshot, 120),
                    _truncate(line.billingSummary, 80),
                  ],
              ],
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
              },
            ),
          pw.SizedBox(height: 16),
          pw.Text('Additional work',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (sortedAdd.isEmpty)
            pw.Text('No additional work.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Date',
                'Hours',
                'Description',
                'Linked job',
              ],
              data: [
                for (final line in sortedAdd)
                  [
                    DateFormat('d MMM yyyy').format(line.workDate),
                    _hours.format(line.hours),
                    _truncate(line.description, 100),
                    _linkedJobLabel(line.linkedJobCardNumber, sortedJobs),
                  ],
              ],
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {1: pw.Alignment.centerRight},
            ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['', 'Hours'],
            data: [
              ['Job card work', _hours.format(period.totalJobHours)],
              ['Additional work', _hours.format(period.totalAdditionalHours)],
              [
                'Total',
                _hours.format(period.totalHours),
              ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
            },
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Generated $generated — PDF version ${period.pdfVersion + 1}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/timesheet_${period.clockNo}_${period.periodKey}_${_fileDate.format(DateTime.now())}.pdf',
    );
    await file.writeAsBytes(await doc.save());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'My Timesheet — $periodLabel — ${period.employeeName}',
    );
    return file;
  }

  static String _truncate(String text, int max) {
    final t = text.replaceAll('\n', ' ').trim();
    if (t.length <= max) return t.isEmpty ? '—' : t;
    return '${t.substring(0, max - 1)}…';
  }

  static String _linkedJobLabel(
    int? jobNumber,
    List<WorkReportJobLine> jobLines,
  ) {
    if (jobNumber == null) return '—';
    for (final line in jobLines) {
      if (line.jobCardNumber == jobNumber) {
        final machine = line.jobMeta.machine.trim();
        if (machine.isNotEmpty) return '#$jobNumber · $machine';
        final loc = line.jobMeta.locationLabel.trim();
        if (loc.isNotEmpty) return '#$jobNumber · $loc';
        break;
      }
    }
    return '#$jobNumber';
  }
}