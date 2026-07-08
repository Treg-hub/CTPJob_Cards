import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/work_report_period_utils.dart';

void main() {
  group('calendar month', () {
    test('period key and bounds', () {
      expect(
        WorkReportPeriodUtils.periodKeyFor(DateTime(2026, 7, 15)),
        '2026-07',
      );
      expect(
        WorkReportPeriodUtils.periodStart('2026-07'),
        DateTime(2026, 7, 1),
      );
      final end = WorkReportPeriodUtils.periodEnd('2026-07');
      expect(end.month, 7);
      expect(end.day, 31);
    });

    test('selectable includes current + prior', () {
      final keys = WorkReportPeriodUtils.selectablePeriodKeys(
        editablePeriodsBack: 1,
        now: DateTime(2026, 7, 8),
      );
      expect(keys, ['2026-07', '2026-06']);
    });
  });

  group('factory month (26th–25th)', () {
    test('period key for day before open is previous open month', () {
      // 10 Jul → still in period that opened 26 Jun → key 2026-06
      expect(
        WorkReportPeriodUtils.periodKeyFor(
          DateTime(2026, 7, 10),
          periodMode: WorkReportPeriodUtils.modeFactoryMonth,
          periodStartDay: 26,
        ),
        '2026-06',
      );
      // 26 Jul → opens 2026-07
      expect(
        WorkReportPeriodUtils.periodKeyFor(
          DateTime(2026, 7, 26),
          periodMode: WorkReportPeriodUtils.modeFactoryMonth,
          periodStartDay: 26,
        ),
        '2026-07',
      );
    });

    test('bounds 26 Jun – 25 Jul', () {
      final start = WorkReportPeriodUtils.periodStart(
        '2026-06',
        periodMode: WorkReportPeriodUtils.modeFactoryMonth,
        periodStartDay: 26,
      );
      final end = WorkReportPeriodUtils.periodEnd(
        '2026-06',
        periodMode: WorkReportPeriodUtils.modeFactoryMonth,
        periodStartDay: 26,
      );
      expect(start, DateTime(2026, 6, 26));
      expect(end.month, 7);
      expect(end.day, 25);
    });
  });
}
