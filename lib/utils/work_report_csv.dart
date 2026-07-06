import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/work_report_additional_line.dart';
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
    required List<WorkReportAdditionalLine> additionalLines,
    required WorkReportSettings settings,
  }) {
    final jobs = filterJobLines(jobLines, settings)
      ..sort((a, b) => a.jobCardNumber.compareTo(b.jobCardNumber));
    final add = [...additionalLines]
      ..sort((a, b) => a.workDate.compareTo(b.workDate));

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
      ['Section', 'Job #', 'Type', 'Location', 'Date', 'Hours', 'Description', 'Billing summary', 'Linked job #'],
    ];

    for (final line in jobs) {
      rows.add([
        'Job card',
        line.jobCardNumber > 0 ? line.jobCardNumber : '',
        line.jobMeta.type,
        line.jobMeta.locationLabel,
        '',
        _hours.format(line.hours),
        line.correctiveActionSnapshot.replaceAll('\n', ' '),
        line.billingSummary.replaceAll('\n', ' '),
        '',
      ]);
    }

    for (final line in add) {
      rows.add([
        'Additional',
        '',
        '',
        '',
        DateFormat('yyyy-MM-dd').format(line.workDate),
        _hours.format(line.hours),
        line.description.replaceAll('\n', ' '),
        '',
        line.linkedJobCardNumber ?? '',
      ]);
    }

    rows.addAll([
      [],
      ['Summary', 'Job card hours', _hours.format(period.totalJobHours)],
      ['Summary', 'Additional hours', _hours.format(period.totalAdditionalHours)],
      ['Summary', 'Total hours', _hours.format(period.totalHours)],
      [],
      ['Generated', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())],
    ]);

    return const CsvEncoder().convert(rows);
  }

  static Future<File> generateAndShare({
    required WorkReportPeriod period,
    required List<WorkReportJobLine> jobLines,
    required List<WorkReportAdditionalLine> additionalLines,
    required WorkReportSettings settings,
  }) async {
    final csv = buildCsv(
      period: period,
      jobLines: jobLines,
      additionalLines: additionalLines,
      settings: settings,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/timesheet_${period.clockNo}_${period.periodKey}_${_fileDate.format(DateTime.now())}.csv',
    );
    await file.writeAsString(csv);
    final periodLabel = WorkReportPeriodUtils.periodLabel(period.periodKey);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'My Timesheet CSV — $periodLabel — ${period.employeeName}',
    );
    return file;
  }
}