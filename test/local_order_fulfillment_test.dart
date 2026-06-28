import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/utils/ink_po_fulfillment.dart';

void main() {
  group('deductReceiptFromPurchaseOrder', () {
    test('deducts item qty from remaining', () {
      final result = deductReceiptFromPurchaseOrder(
        remainingKgByItem: {'toloul': 2000},
        itemCode: 'toloul',
        quantity: 500,
      );
      expect(result.remainingKgByItem['toloul'], 1500);
      expect(result.status, 'partially_fulfilled');
    });

    test('clamps remaining at zero on over-receipt', () {
      final result = deductReceiptFromPurchaseOrder(
        remainingKgByItem: {'toloul': 200},
        itemCode: 'toloul',
        quantity: 500,
      );
      expect(result.remainingKgByItem['toloul'], 0);
    });

    test('marks fulfilled at threshold', () {
      final result = deductReceiptFromPurchaseOrder(
        remainingKgByItem: {'toloul': inkPoFulfilledThreshold},
        itemCode: 'toloul',
        quantity: inkPoFulfilledThreshold,
      );
      expect(result.status, 'fulfilled');
    });

    test('stays partially_fulfilled when another line open', () {
      final result = deductReceiptFromPurchaseOrder(
        remainingKgByItem: {'toloul': 1000, 'other': 500},
        itemCode: 'toloul',
        quantity: 1000,
      );
      expect(result.remainingKgByItem['toloul'], 0);
      expect(result.remainingKgByItem['other'], 500);
      expect(result.status, 'partially_fulfilled');
    });
  });
}