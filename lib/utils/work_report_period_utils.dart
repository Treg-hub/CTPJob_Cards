/// Weekly (and legacy monthly) helpers for My Timesheet.
///
/// Primary product mode is **calendar week** (Monday–Sunday).
/// Period key: `YYYY-Www` (ISO week, e.g. `2026-W28`).
///
/// Legacy keys `YYYY-MM` are still parsed for old docs; new writes use weeks.
class WorkReportPeriodUtils {
  WorkReportPeriodUtils._();

  static const String modeCalendarWeek = 'calendar_week';
  static const String modeCalendarMonth = 'calendar_month';
  static const String modeFactoryMonth = 'factory_month';

  /// Default lookback: current week + N prior weeks.
  static const int defaultEditablePeriodsBack = 8;

  static bool isWeekKey(String periodKey) =>
      RegExp(r'^\d{4}-W\d{2}$').hasMatch(periodKey);

  static bool isMonthKey(String periodKey) =>
      RegExp(r'^\d{4}-\d{2}$').hasMatch(periodKey) && !isWeekKey(periodKey);

  /// Monday 00:00 local of the ISO week containing [date].
  static DateTime weekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// Sunday 23:59:59.999 local of the week starting [monday].
  static DateTime weekEndFromMonday(DateTime monday) {
    final start = DateTime(monday.year, monday.month, monday.day);
    return start
        .add(const Duration(days: 7))
        .subtract(const Duration(milliseconds: 1));
  }

  /// ISO week key for [date] → `YYYY-Www`.
  static String weekKeyFor(DateTime date) {
    final monday = weekStart(date);
    // ISO week year is the year of the Thursday of this week.
    final thursday = monday.add(const Duration(days: 3));
    final isoYear = thursday.year;
    final jan4 = DateTime(isoYear, 1, 4);
    final week1Monday = weekStart(jan4);
    final weekNum = monday.difference(week1Monday).inDays ~/ 7 + 1;
    return '$isoYear-W${weekNum.toString().padLeft(2, '0')}';
  }

  /// Monday of ISO week from key `YYYY-Www`.
  static DateTime mondayOfWeekKey(String periodKey) {
    final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(periodKey);
    if (match == null) {
      throw FormatException('Invalid week period key: $periodKey');
    }
    final year = int.parse(match.group(1)!);
    final week = int.parse(match.group(2)!);
    final jan4 = DateTime(year, 1, 4);
    final week1Monday = weekStart(jan4);
    return week1Monday.add(Duration(days: (week - 1) * 7));
  }

  static String periodKeyFor(
    DateTime date, {
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    // Product default is weekly. Legacy month modes only if explicitly requested.
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      if (date.day >= periodStartDay) {
        return _ym(date.year, date.month);
      }
      final prev = DateTime(date.year, date.month - 1, 1);
      return _ym(prev.year, prev.month);
    }
    if (periodMode == modeCalendarMonth) {
      return _ym(date.year, date.month);
    }
    return weekKeyFor(date);
  }

  static String _ym(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  static DateTime periodStart(
    String periodKey, {
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    if (isWeekKey(periodKey)) {
      return mondayOfWeekKey(periodKey);
    }
    // Legacy month keys
    final parts = periodKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      return DateTime(year, month, periodStartDay);
    }
    return DateTime(year, month, 1);
  }

  static DateTime periodEnd(
    String periodKey, {
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    if (isWeekKey(periodKey)) {
      return weekEndFromMonday(mondayOfWeekKey(periodKey));
    }
    if (periodMode == modeFactoryMonth && periodStartDay > 1) {
      final start = periodStart(
        periodKey,
        periodMode: periodMode,
        periodStartDay: periodStartDay,
      );
      final nextOpen = DateTime(start.year, start.month + 1, periodStartDay);
      return nextOpen.subtract(const Duration(milliseconds: 1));
    }
    final start = periodStart(periodKey, periodMode: modeCalendarMonth);
    final next = DateTime(start.year, start.month + 1, 1);
    return next.subtract(const Duration(milliseconds: 1));
  }

  static String periodDocId(String clockNo, String periodKey) =>
      '${clockNo}_$periodKey';

  static String periodLabel(
    String periodKey, {
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (isWeekKey(periodKey)) {
      final start = mondayOfWeekKey(periodKey);
      final end = DateTime(start.year, start.month, start.day + 6);
      final sameYear = start.year == end.year;
      final left = '${start.day} ${months[start.month - 1]}';
      final right = sameYear
          ? '${end.day} ${months[end.month - 1]} ${end.year}'
          : '${end.day} ${months[end.month - 1]} ${end.year}';
      return '$left – $right';
    }
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
    final start = periodStart(periodKey, periodMode: modeCalendarMonth);
    const longMonths = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${longMonths[start.month - 1]} ${start.year}';
  }

  /// Short label for app bar / chips, e.g. "Week of 7 Jul".
  static String periodShortLabel(String periodKey) {
    if (isWeekKey(periodKey)) {
      final start = mondayOfWeekKey(periodKey);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return 'Week of ${start.day} ${months[start.month - 1]}';
    }
    return periodLabel(periodKey);
  }

  /// Current period and [editablePeriodsBack] prior periods (weeks by default).
  static List<String> selectablePeriodKeys({
    int editablePeriodsBack = defaultEditablePeriodsBack,
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final mode = _effectiveMode(periodMode);
    final keys = <String>[
      periodKeyFor(n, periodMode: mode, periodStartDay: periodStartDay),
    ];
    var cursor = periodStart(
      keys.first,
      periodMode: mode,
      periodStartDay: periodStartDay,
    );
    for (var i = 0; i < editablePeriodsBack; i++) {
      cursor = cursor.subtract(const Duration(days: 1));
      keys.add(
        periodKeyFor(
          cursor,
          periodMode: mode,
          periodStartDay: periodStartDay,
        ),
      );
      cursor = periodStart(
        keys.last,
        periodMode: mode,
        periodStartDay: periodStartDay,
      );
    }
    return keys;
  }

  static String _effectiveMode(String periodMode) {
    if (periodMode == modeCalendarMonth || periodMode == modeFactoryMonth) {
      // Product is weekly; treat legacy setting as week.
      return modeCalendarWeek;
    }
    return modeCalendarWeek;
  }

  static bool isPeriodEditable(
    String periodKey, {
    int editablePeriodsBack = defaultEditablePeriodsBack,
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    return selectablePeriodKeys(
      editablePeriodsBack: editablePeriodsBack,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    ).contains(periodKey);
  }

  /// True when [periodKey] is the period containing "now".
  static bool isCurrentPeriod(
    String periodKey, {
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final current = periodKeyFor(
      n,
      periodMode: _effectiveMode(periodMode),
      periodStartDay: periodStartDay,
    );
    return periodKey == current;
  }

  /// True when the period is earlier than the current one (still may be editable).
  static bool isPastPeriod(
    String periodKey, {
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
    DateTime? now,
  }) {
    if (isCurrentPeriod(
      periodKey,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
      now: now,
    )) {
      return false;
    }
    final n = now ?? DateTime.now();
    final currentStart = periodStart(
      periodKeyFor(
        n,
        periodMode: _effectiveMode(periodMode),
        periodStartDay: periodStartDay,
      ),
      periodMode: _effectiveMode(periodMode),
      periodStartDay: periodStartDay,
    );
    final keyStart = periodStart(
      periodKey,
      periodMode: _effectiveMode(periodMode),
      periodStartDay: periodStartDay,
    );
    return keyStart.isBefore(currentStart);
  }

  /// Step one period earlier (for navigator). Null if outside lookback.
  static String? previousPeriodKey(
    String periodKey, {
    int editablePeriodsBack = defaultEditablePeriodsBack,
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    final keys = selectablePeriodKeys(
      editablePeriodsBack: editablePeriodsBack,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    final i = keys.indexOf(periodKey);
    if (i < 0 || i >= keys.length - 1) return null;
    return keys[i + 1];
  }

  /// Step one period later (toward current). Null if already current.
  static String? nextPeriodKey(
    String periodKey, {
    int editablePeriodsBack = defaultEditablePeriodsBack,
    String periodMode = modeCalendarWeek,
    int periodStartDay = 1,
  }) {
    final keys = selectablePeriodKeys(
      editablePeriodsBack: editablePeriodsBack,
      periodMode: periodMode,
      periodStartDay: periodStartDay,
    );
    final i = keys.indexOf(periodKey);
    if (i <= 0) return null;
    return keys[i - 1];
  }

  static bool isDateInPeriod(
    DateTime date,
    String periodKey, {
    String periodMode = modeCalendarWeek,
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

  /// Working-day estimate for soft hour guidance (Mon–Fri in range).
  static int workingDaysInPeriod(
    String periodKey, {
    String periodMode = modeCalendarWeek,
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
