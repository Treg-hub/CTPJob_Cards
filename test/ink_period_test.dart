import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/models/ink_count_event.dart';
import 'package:ctp_job_cards/utils/ink_period.dart';

InkCountEvent _event(DateTime countDate) => InkCountEvent(
      countDate: countDate,
      sessionId: 's',
      actorClockNo: '1',
      actorName: 'Test',
      adjustmentCount: 0,
      lines: const [],
      createdAt: countDate,
    );

void main() {
  group('inkOpenPeriodRange', () {
    test('no counts — unbounded', () {
      final range = inkOpenPeriodRange([]);
      expect(range.fromExclusive, isNull);
      expect(range.toInclusive, isNull);
      expect(isWithinInkOpenPeriod(DateTime(2020), range), isTrue);
    });

    test('open period starts after latest count', () {
      final count = DateTime(2026, 5, 28, 12, 1);
      final range = inkOpenPeriodRange([_event(count)]);
      expect(range.fromExclusive, count);
      expect(isWithinInkOpenPeriod(count, range), isFalse);
      expect(isWithinInkOpenPeriod(count.add(const Duration(seconds: 1)), range),
          isTrue);
    });
  });
}