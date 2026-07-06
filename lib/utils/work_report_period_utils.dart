/// Calendar-month period helpers for My Timesheet.
class WorkReportPeriodUtils {
  WorkReportPeriodUtils._();

  static String periodKeyFor(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  static DateTime periodStart(String periodKey) {
    final parts = periodKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return DateTime(year, month, 1);
  }

  static DateTime periodEnd(String periodKey) {
    final start = periodStart(periodKey);
    final next = DateTime(start.year, start.month + 1, 1);
    return next.subtract(const Duration(milliseconds: 1));
  }

  static String periodDocId(String clockNo, String periodKey) =>
      '${clockNo}_$periodKey';

  static String periodLabel(String periodKey) {
    final start = periodStart(periodKey);
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[start.month - 1]} ${start.year}';
  }

  /// Current calendar month and [editablePeriodsBack] prior months.
  static List<String> selectablePeriodKeys({int editablePeriodsBack = 1}) {
    final now = DateTime.now();
    final keys = <String>[periodKeyFor(now)];
    var cursor = DateTime(now.year, now.month - 1, 1);
    for (var i = 0; i < editablePeriodsBack; i++) {
      keys.add(periodKeyFor(cursor));
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    return keys;
  }

  static bool isPeriodEditable(
    String periodKey, {
    int editablePeriodsBack = 1,
  }) {
    return selectablePeriodKeys(editablePeriodsBack: editablePeriodsBack)
        .contains(periodKey);
  }

  static bool isDateInPeriod(DateTime date, String periodKey) {
    final start = periodStart(periodKey);
    final end = periodEnd(periodKey);
    return !date.isBefore(start) && !date.isAfter(end);
  }
}