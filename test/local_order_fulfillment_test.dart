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

  group('applyShipmentDeduction', () {
    test('deducts expected kg per shipment line', () {
      final result = applyShipmentDeduction(
        remainingKgByItem: {'black': 3000, 'yellow': 8000},
        lines: const [
          (itemCode: 'black', expectedKg: 1000),
          (itemCode: 'yellow', expectedKg: 2000),
        ],
        linkedShipmentIds: const [],
        shipmentId: '51993-K',
      );
      expect(result.remainingKgByItem['black'], 2000);
      expect(result.remainingKgByItem['yellow'], 6000);
      expect(result.status, 'partially_fulfilled');
      expect(result.linkedShipmentIds, ['51993-K']);
    });

    test('clamps remaining at zero and marks fulfilled', () {
      final result = applyShipmentDeduction(
        remainingKgByItem: {'black': 500},
        lines: const [(itemCode: 'black', expectedKg: 600)],
        linkedShipmentIds: const ['51993-J'],
        shipmentId: '51993-K',
      );
      expect(result.remainingKgByItem['black'], 0);
      expect(result.status, 'fulfilled');
      expect(result.linkedShipmentIds, containsAll(['51993-J', '51993-K']));
    });

    test('skips lines with empty item code', () {
      final result = applyShipmentDeduction(
        remainingKgByItem: {'black': 1000},
        lines: const [(itemCode: '', expectedKg: 500)],
        linkedShipmentIds: const [],
        shipmentId: '51993-K',
      );
      expect(result.remainingKgByItem['black'], 1000);
    });
  });
}