import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/work_report_additional_line.dart';
import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import 'work_report_csv.dart';
import 'work_report_daily_hours.dart';
import 'work_report_period_utils.dart';

class WorkReportPdfExporter {
  static final _hours = NumberFormat('#,##0.##');
  static final _fileDate = DateFormat('yyyy-MM-dd_HHmm');

  static Future<Uint8List> buildPdfBytes({
    required WorkReportPeriod period,
    required List<WorkReportJobLine> jobLines,
    required List<WorkReportAdditionalLine> additionalLines,
    required WorkReportSettings settings,
    int postPdfEditCount = 0,
  }) async {
    final doc = pw.Document();
    final periodLabel = WorkReportPeriodUtils.periodLabel(period.periodKey);
    final fromStr = DateFormat('d MMM yyyy').format(period.periodStart);
    final toStr = DateFormat('d MMM yyyy').format(period.periodEnd);
    final generated = DateFormat('d MMM yyyy HH:mm').format(DateTime.now());

    final sortedJobs = WorkReportCsvExporter.filterJobLines(jobLines, settings)
      ..sort((a, b) => a.jobCardNumber.compareTo(b.jobCardNumber));
    final sortedAdd = [...additionalLines]
      ..sort((a, b) => a.workDate.compareTo(b.workDate));
    final daily = WorkReportDailyHours.fromAdditionalLines(sortedAdd);

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
          if (period.hasPdf &&
              settings.includePostPdfEditNote &&
              postPdfEditCount > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Note: $postPdfEditCount admin edit(s) logged after the last PDF '
              '(v${period.pdfVersion}). Verify totals before payment.',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.orange800),
            ),
          ],
          if (daily.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Additional work by day',
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in daily)
                  pw.Container(
                    padding:
                        const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      d.chipLabel(_hours.format(d.hours)),
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ),
              ],
            ),
          ],
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
                    _clean(line.jobMeta.locationLabel),
                    _hours.format(line.hours),
                    _clean(line.correctiveActionSnapshot),
                    _clean(line.billingSummary),
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
              columnWidths: {
                4: const pw.FlexColumnWidth(2.2),
                5: const pw.FlexColumnWidth(1.8),
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
                    _clean(line.description),
                    _linkedJobLabel(line.linkedJobCardNumber, sortedJobs),
                  ],
              ],
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {1: pw.Alignment.centerRight},
              columnWidths: {2: const pw.FlexColumnWidth(2.5)},
            ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['', 'Hours'],
            data: [
              ['Job card work', _hours.format(period.totalJobHours)],
              ['Additional work', _hours.format(period.totalAdditionalHours)],
              ['Total', _hours.format(period.totalHours)],
            ],
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
            },
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
          if (settings.includeSignatureBlock) ...[
            pw.SizedBox(height: 24),
            pw.Text('Approval',
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 200,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey600),
                        ),
                      ),
                      height: 28,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Worker signature / date',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(period.employeeName,
                        style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 200,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey600),
                        ),
                      ),
                      height: 28,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Accounts / manager approval',
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Text(
            'Generated $generated — PDF version ${period.pdfVersion + 1}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<File> writePdfFile({
    required Uint8List bytes,
    required WorkReportPeriod period,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/timesheet_${period.clockNo}_${period.periodKey}_${_fileDate.format(DateTime.now())}.pdf',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<File> sharePdfFile({
    required File file,
    required WorkReportPeriod period,
  }) async {
    final periodLabel = WorkReportPeriodUtils.periodLabel(period.periodKey);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'My Timesheet — $periodLabel — ${period.employeeName}',
      ),
    );
    return file;
  }

  static String _clean(String text) {
    final t = text.replaceAll('\n', ' ').trim();
    return t.isEmpty ? '—' : t;
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