import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/models/ink_count_event.dart';
import 'package:ctp_job_cards/models/ink_transaction.dart';
import 'package:ctp_job_cards/models/ink_txn_type.dart';
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

InkTransaction _txn(DateTime effectiveAt) => InkTransaction(
      type: InkTxnType.purchase,
      stockItemCode: 'toloul',
      quantityDelta: 10,
      effectiveAt: effectiveAt,
      costStatus: InkCostStatus.costed,
      actorClockNo: '1',
      actorName: 'Test',
      idempotencyKey: 'k',
    );

void main() {
  test('ledger recent list filters to open count period', () {
    final count = DateTime(2026, 5, 28, 12, 1);
    final range = inkOpenPeriodRange([_event(count)]);
    final recent = [
      _txn(count.subtract(const Duration(days: 1))),
      _txn(count.add(const Duration(seconds: 1))),
      _txn(count.add(const Duration(days: 3))),
    ];

    final inPeriod =
        recent.where((t) => isWithinInkOpenPeriod(t.effectiveAt, range)).toList();

    expect(inPeriod, hasLength(2));
    expect(inPeriod.every((t) => t.effectiveAt.isAfter(count)), isTrue);
  });
}