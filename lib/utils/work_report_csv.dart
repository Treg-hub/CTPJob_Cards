import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import '../utils/work_report_period_utils.dart';

class WorkReportCsvExporter {
  static final _hours = NumberFormat('#,##0.##');
  static final _fileDate = DateFormat('yyyy-MM-dd_HHmm');

  static List<WorkReportJobLine> filterJobLines(
    List<WorkReportJobLine> lines,
    WorkReportSettings settings,
  ) {
    if (settings.includeZeroHourJobs) return lines;
    return lines.where((l) => l.hours > 0).toList();
  }

  static String buildCsv({
    required WorkReportPeriod period,
    required List<WorkReportJobLine> jobLines,
    required WorkReportSettings settings,
  }) {
    final jobs = filterJobLines(jobLines, settings)
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

    final rows = <List<dynamic>>[
      ['CTP My Timesheet'],
      [WorkReportPeriodUtils.periodLabel(period.periodKey)],
      [
        'Name',
        period.employeeName,
        'Clock',
        period.clockNo,
        'Department',
        period.department,
        'Position',
        period.position,
      ],
      [],
      [
        'Job #',
        'Type',
        'Location',
        'Work date',
        'Hours',
        'Work done',
        'Billing summary',
      ],
    ];

    for (final line in jobs) {
      rows.add([
        line.jobCardNumber > 0 ? line.jobCardNumber : '',
        line.jobMeta.type,
        line.jobMeta.locationLabel,
        line.workDate != null
            ? DateFormat('yyyy-MM-dd').format(line.workDate!)
            : '',
        _hours.format(line.hours),
        line.correctiveActionSnapshot.replaceAll('\n', ' '),
        line.billingSummary.replaceAll('\n', ' '),
      ]);
    }

    rows.addAll([
      [],
      ['Summary', 'Total hours', _hours.format(period.totalHours)],
      [],
      ['Generated', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())],
    ]);

    return const CsvEncoder().convert(rows);
  }

  static Future<File> generateAndShare({
    required WorkReportPeriod period,
    required List<WorkReportJobLine> jobLines,
    required WorkReportSettings settings,
  }) async {
    final csv = buildCsv(
      period: period,
      jobLines: jobLines,
      settings: settings,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/timesheet_${period.clockNo}_${period.periodKey}_${_fileDate.format(DateTime.now())}.csv',
    );
    await file.writeAsString(csv);
    final periodLabel = WorkReportPeriodUtils.periodLabel(period.periodKey);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'My Timesheet CSV — $periodLabel — ${period.employeeName}',
      ),
    );
    return file;
  }
}
