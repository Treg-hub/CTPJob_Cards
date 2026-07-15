import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import 'work_report_csv.dart';
import 'work_report_daily_hours.dart';
import 'work_report_period_utils.dart';

/// Brand accent for timesheet PDF headers (matches CTP orange, printable).
const PdfColor _kBrand = PdfColor.fromInt(0xFFC25F3A);
const PdfColor _kHeaderBg = PdfColor.fromInt(0xFFF3F4F6);
const PdfColor _kBorder = PdfColor.fromInt(0xFFD1D5DB);
const PdfColor _kMuted = PdfColor.fromInt(0xFF6B7280);

class WorkReportPdfExporter {
  static final _hours = NumberFormat('#,##0.##');
  static final _fileDate = DateFormat('yyyy-MM-dd_HHmm');
  static final _day = DateFormat('d MMM yyyy');

  /// Helvetica (default pdf fonts) only cover WinAnsi — map common Unicode
  /// that otherwise renders as empty boxes (tofu).
  static String pdfSafe(String text) {
    var t = text
        .replaceAll('\u2014', '-') // em dash
        .replaceAll('\u2013', '-') // en dash
        .replaceAll('\u2212', '-') // minus
        .replaceAll('\u00A0', ' ') // nbsp
        .replaceAll('\u2022', '-') // bullet
        .replaceAll('\u2026', '...') // ellipsis
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u00B7', '.') // middle dot
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Drop remaining non-Latin1 that would become boxes.
    t = t.replaceAllMapped(
      RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'),
      (_) => '',
    );
    return t;
  }

  static String _cell(String text, {String empty = ''}) {
    final t = pdfSafe(text);
    return t.isEmpty ? empty : t;
  }

  static Future<Uint8List> buildPdfBytes({
    required WorkReportPeriod period,
    required List<WorkReportJobLine> jobLines,
    required WorkReportSettings settings,
    int postPdfEditCount = 0,
  }) async {
    final doc = pw.Document(
      title: pdfSafe(
        'CTP Timesheet ${period.clockNo} ${period.periodKey}',
      ),
      author: 'CTP Job Cards',
    );

    final periodLabel = pdfSafe(
      WorkReportPeriodUtils.periodLabel(period.periodKey),
    );
    final fromStr = _day.format(period.periodStart);
    final toStr = _day.format(period.periodEnd);
    final generated = DateFormat('d MMM yyyy HH:mm').format(DateTime.now());

    final sortedJobs = WorkReportCsvExporter.filterJobLines(jobLines, settings)
      ..sort((a, b) {
        final da = a.workDate;
        final db = b.workDate;
        if (da != null && db != null) {
          final c = da.compareTo(db);
          if (c != 0) return c;
        } else if (da != null) {
          return -1;
        } else if (db != null) {
          return 1;
        }
        return a.jobCardNumber.compareTo(b.jobCardNumber);
      });

    // Only show daily chips with hours > 0 (cleaner for Accounts).
    final daily = WorkReportDailyHours.fromJobLines(sortedJobs)
        .where((d) => d.hours > 0.001)
        .toList();

    final notes = pdfSafe(period.notes);
    final totalHours = period.totalHours > 0
        ? period.totalHours
        : sortedJobs.fold<double>(0, (s, l) => s + l.hours);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 32),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                pdfSafe(
                  'Generated $generated | PDF v${period.pdfVersion + 1}',
                ),
                style: const pw.TextStyle(fontSize: 8, color: _kMuted),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: _kMuted),
              ),
            ],
          ),
        ),
        build: (context) => [
          // --- Header band ---
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: pw.BoxDecoration(
              color: _kBrand,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CTP Job Cards',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'My Timesheet',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      periodLabel,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      pdfSafe('$fromStr - $toStr'),
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // --- Worker details ---
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kBorder),
              borderRadius: pw.BorderRadius.circular(4),
              color: _kHeaderBg,
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _metaLine('Name', period.employeeName),
                      pw.SizedBox(height: 4),
                      _metaLine('Department', period.department),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _metaLine('Clock', period.clockNo),
                      pw.SizedBox(height: 4),
                      _metaLine('Position', period.position),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: _kBorder),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'Total hours',
                        style: const pw.TextStyle(fontSize: 8, color: _kMuted),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        _hours.format(totalHours),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: _kBrand,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (period.hasPdf &&
              settings.includePostPdfEditNote &&
              postPdfEditCount > 0) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF7ED),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFFDBA74)),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                pdfSafe(
                  'Note: $postPdfEditCount edit(s) logged after the last PDF '
                  '(v${period.pdfVersion}). Verify totals before payment.',
                ),
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColor.fromInt(0xFF9A3412),
                ),
              ),
            ),
          ],

          if (daily.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Hours by day',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in daily)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _kHeaderBg,
                      border: pw.Border.all(color: _kBorder),
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      pdfSafe(d.chipLabel(_hours.format(d.hours))),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
              ],
            ),
          ],

          pw.SizedBox(height: 14),
          pw.Text(
            'Job card work',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),

          if (sortedJobs.isEmpty)
            pw.Text(
              'No job card lines for this week.',
              style: const pw.TextStyle(fontSize: 9, color: _kMuted),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Job #',
                'Date',
                'Type',
                'Location',
                'Hours',
                'Work done',
                'Billing',
              ],
              data: [
                for (final line in sortedJobs)
                  [
                    line.jobCardNumber > 0 ? '#${line.jobCardNumber}' : '',
                    line.workDate != null ? _day.format(line.workDate!) : '',
                    _cell(line.jobMeta.type),
                    _cell(line.jobMeta.locationLabel),
                    _hours.format(line.hours),
                    _cell(line.correctiveActionSnapshot),
                    _cell(line.billingSummary),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _kBrand),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 5,
              ),
              border: pw.TableBorder.all(color: _kBorder, width: 0.5),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFAFAFA),
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FixedColumnWidth(58),
                2: const pw.FlexColumnWidth(1.1),
                3: const pw.FlexColumnWidth(1.8),
                4: const pw.FixedColumnWidth(36),
                5: const pw.FlexColumnWidth(2.2),
                6: const pw.FlexColumnWidth(1.4),
              },
            ),

          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 160,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _kBorder),
                borderRadius: pw.BorderRadius.circular(4),
                color: _kHeaderBg,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${_hours.format(totalHours)} h',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _kBrand,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- Notes (typed + room to write) ---
          pw.SizedBox(height: 16),
          pw.Text(
            'Notes',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Optional comments for Accounts / manager (or write below).',
            style: const pw.TextStyle(fontSize: 8, color: _kMuted),
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            constraints: const pw.BoxConstraints(minHeight: 72),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kBorder),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (notes.isNotEmpty)
                  pw.Text(notes, style: const pw.TextStyle(fontSize: 9))
                else
                  pw.Text(
                    ' ',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                // Ruled lines for handwritten notes
                for (var i = 0; i < (notes.isEmpty ? 4 : 2); i++) ...[
                  pw.SizedBox(height: 14),
                  pw.Container(
                    width: double.infinity,
                    height: 0.6,
                    color: _kBorder,
                  ),
                ],
              ],
            ),
          ),

          if (settings.includeSignatureBlock) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              'Approval',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _signatureBlock(
                  label: 'Worker signature / date',
                  subtitle: pdfSafe(period.employeeName),
                ),
                _signatureBlock(
                  label: 'Accounts / manager approval',
                  subtitle: '',
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _metaLine(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _kMuted,
            ),
          ),
          pw.TextSpan(
            text: _cell(value, empty: '-'),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock({
    required String label,
    required String subtitle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 210,
          height: 32,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.8),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _kMuted)),
        if (subtitle.isNotEmpty)
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 8)),
      ],
    );
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
        subject: pdfSafe(
          'My Timesheet - $periodLabel - ${period.employeeName}',
        ),
      ),
    );
    return file;
  }
}
