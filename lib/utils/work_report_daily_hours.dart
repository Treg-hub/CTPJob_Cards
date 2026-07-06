import 'package:intl/intl.dart';

import '../models/work_report_additional_line.dart';

class WorkReportDailyHours {
  const WorkReportDailyHours({
    required this.date,
    required this.hours,
  });

  final DateTime date;
  final double hours;

  String get dayLabel => DateFormat('EEE d MMM').format(date);

  String chipLabel(String hoursFmt) => '$dayLabel ${hoursFmt}h';

  static List<WorkReportDailyHours> fromAdditionalLines(
    List<WorkReportAdditionalLine> lines,
  ) {
    final byDay = <String, double>{};
    final dates = <String, DateTime>{};
    for (final line in lines) {
      final d = DateTime(line.workDate.year, line.workDate.month, line.workDate.day);
      final key = '${d.year}-${d.month}-${d.day}';
      byDay[key] = (byDay[key] ?? 0) + line.hours;
      dates[key] = d;
    }
    final out = <WorkReportDailyHours>[];
    for (final entry in byDay.entries) {
      out.add(WorkReportDailyHours(date: dates[entry.key]!, hours: entry.value));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }
}