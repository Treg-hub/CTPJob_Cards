import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/models/ink_count_event.dart';
import 'package:ctp_job_cards/models/ink_ibc.dart';
import 'package:ctp_job_cards/utils/ink_ibc_period.dart';
import 'package:ctp_job_cards/utils/ink_period.dart';

InkIbc _ibc({
  required String code,
  required InkIbcStatus status,
  DateTime? transferredDate,
}) =>
    InkIbc(
      ibcNumber: '12345678',
      itemCode: code,
      kg: 1000,
      status: status,
      receivedDate: DateTime(2026, 1, 1),
      transferredDate: transferredDate,
    );

void main() {
  test('isIbcConsumedInOpenPeriod respects count boundary', () {
    final count = DateTime(2026, 5, 28);
    final range = inkOpenPeriodRange([
      InkCountEvent(
        countDate: count,
        sessionId: 's',
        actorClockNo: '1',
        actorName: 'T',
        adjustmentCount: 0,
        lines: const [],
        createdAt: count,
      ),
    ]);

    expect(
      isIbcConsumedInOpenPeriod(
        _ibc(
          code: 'yellow',
          status: InkIbcStatus.transferred,
          transferredDate: count,
        ),
        range,
      ),
      isFalse,
    );
    expect(
      isIbcConsumedInOpenPeriod(
        _ibc(
          code: 'yellow',
          status: InkIbcStatus.transferred,
          transferredDate: count.add(const Duration(hours: 1)),
        ),
        range,
      ),
      isTrue,
    );
    expect(
      isIbcConsumedInOpenPeriod(
        _ibc(code: 'yellow', status: InkIbcStatus.received),
        range,
      ),
      isFalse,
    );
  });

  test('ibcConsumedCountByColour groups transferred in period', () {
    final range = (fromExclusive: null, toInclusive: null);
    final all = [
      _ibc(
        code: 'yellow',
        status: InkIbcStatus.transferred,
        transferredDate: DateTime(2026, 6, 1),
      ),
      _ibc(
        code: 'yellow',
        status: InkIbcStatus.transferred,
        transferredDate: DateTime(2026, 6, 2),
      ),
      _ibc(code: 'red', status: InkIbcStatus.received),
    ];
    expect(ibcConsumedCountByColour(all, range), {'yellow': 2});
  });
}