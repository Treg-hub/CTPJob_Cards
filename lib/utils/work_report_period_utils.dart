/// Calendar-month and optional factory pay-period helpers for My Timesheet.
///
/// [timezone] is advisory for labels; wall-clock boundaries use the device
/// local calendar aligned to the factory convention (Africa/Johannesburg
/// workers are expected to keep device TZ correct). Factory pay periods use
/// [periodStartDay] (e.g. 26 → 26th of prior month through 25th).
class WorkReportPeriodUtils {
  WorkReportPeriodUtils._();

  static const String modeCalendarMonth = 'calendar_month';
  static const String modeFactoryMonth = 'factory_month';

  static String periodKeyFor(
    DateTime date, {
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      // Period containing [date]: if day >= startDay, period opens this month;
      // else opens previous month. Key = open month YYYY-MM.
      if (date.day >= periodStartDay) {
        return _ym(date.year, date.month);
      }
      final prev = DateTime(date.year, date.month - 1, 1);
      return _ym(prev.year, prev.month);
    }
    return _ym(date.year, date.month);
  }

  static String _ym(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  static DateTime periodStart(
    String periodKey, {
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    final parts = periodKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      // periodKey is the open month (month of the start day).
      return DateTime(year, month, periodStartDay);
    }
    return DateTime(year, month, 1);
  }

  static DateTime periodEnd(
    String periodKey, {
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      final start = periodStart(
        periodKey,
        periodMode: periodMode,
        periodStartDay: periodStartDay,
      );
      // Ends day before next period start (startDay-1 of next month), end of day.
      final nextOpen = DateTime(start.year, start.month + 1, periodStartDay);
      return nextOpen.subtract(const Duration(milliseconds: 1));
    }
    final start = periodStart(periodKey);
    final next = DateTime(start.year, start.month + 1, 1);
    return next.subtract(const Duration(milliseconds: 1));
  }

  static String periodDocId(String clockNo, String periodKey) =>
      '${clockNo}_$periodKey';

  static String periodLabel(
    String periodKey, {
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      final start = periodStart(
        periodKey,
        periodMode: periodMode,
        periodStartDay: periodStartDay,
      );
      final end = periodEnd(
        periodKey,
        periodMode: periodMode,
        periodStartDay: periodStartDay,
      );
      return '${start.day} ${months[start.month - 1]} – '
          '${end.day} ${months[end.month - 1]} ${end.year}';
    }
    final start = periodStart(periodKey);
    return '${months[start.month - 1]} ${start.year}';
  }

  /// Current period and [editablePeriodsBack] prior periods.
  static List<String> selectablePeriodKeys({
    int editablePeriodsBack = 1,
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final keys = <String>[
      periodKeyFor(
        n,
        periodMode: periodMode,
        periodStartDay: periodStartDay,
      ),
    ];
    var cursor = periodStart(
      keys.first,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    for (var i = 0; i < editablePeriodsBack; i++) {
      // Step back one day before current period open → prior period.
      cursor = cursor.subtract(const Duration(days: 1));
      keys.add(
        periodKeyFor(
          cursor,
          periodMode: periodMode,
          periodStartDay: periodStartDay,
        ),
      );
      cursor = periodStart(
        keys.last,
        periodMode: periodMode,
        periodStartDay: periodStartDay,
      );
    }
    return keys;
  }

  static bool isPeriodEditable(
    String periodKey, {
    int editablePeriodsBack = 1,
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    return selectablePeriodKeys(
      editablePeriodsBack: editablePeriodsBack,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    ).contains(periodKey);
  }

  static bool isDateInPeriod(
    DateTime date,
    String periodKey, {
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    final start = periodStart(
      periodKey,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    final end = periodEnd(
      periodKey,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    return !date.isBefore(start) && !date.isAfter(end);
  }

  /// Working-day estimate for soft monthly hour guidance (Mon–Fri in range).
  static int workingDaysInPeriod(
    String periodKey, {
    String periodMode = modeCalendarMonth,
    int periodStartDay = 1,
  }) {
    final start = periodStart(
      periodKey,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    final end = periodEnd(
      periodKey,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    var count = 0;
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!d.isAfter(last)) {
      if (d.weekday >= DateTime.monday && d.weekday <= DateTime.friday) {
        count++;
      }
      d = d.add(const Duration(days: 1));
    }
    return count;
  }
}
