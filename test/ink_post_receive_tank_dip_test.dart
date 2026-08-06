import 'package:ctp_job_cards/models/ink_purchase_order.dart';
import 'package:ctp_job_cards/models/ink_shipment.dart';
import 'package:ctp_job_cards/utils/ink_post_receive_tank_dip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldSuggestPostReceiveTankDip', () {
    test('toloul always suggested', () {
      expect(shouldSuggestPostReceiveTankDip('toloul'), isTrue);
      expect(
        shouldSuggestPostReceiveTankDip('toloul', packagingMode: 'ibc'),
        isTrue,
      );
    });

    test('binder suggested', () {
      expect(shouldSuggestPostReceiveTankDip('gravure_binder'), isTrue);
    });

    test('IBC colours not suggested (stock sits in drums until consume)', () {
      for (final c in ['yellow', 'red', 'blue', 'black']) {
        expect(
          shouldSuggestPostReceiveTankDip(c, packagingMode: 'ibc'),
          isFalse,
          reason: c,
        );
      }
    });

    test('non-IBC colours may be suggested (e.g. pallet bulk)', () {
      expect(
        shouldSuggestPostReceiveTankDip('yellow', packagingMode: 'pallet'),
        isTrue,
      );
    });

    test('non-tank items not suggested', () {
      expect(shouldSuggestPostReceiveTankDip('resink'), isFalse);
      expect(shouldSuggestPostReceiveTankDip('cellulose'), isFalse);
      expect(shouldSuggestPostReceiveTankDip('asp'), isFalse);
    });
  });

  group('dipOfferFromShipment', () {
    test('aggregates received toloul units', () {
      const shipment = InkShipment(
        id: '51993-A',
        orderNumber: '51993',
        containerLetter: 'A',
        packagingMode: 'pallet',
        status: InkShipmentStatus.received,
        receivedUnits: [
          InkReceivedUnit(ref: 'bulk:toloul', itemCode: 'toloul', netKg: 5000),
          InkReceivedUnit(ref: 'bulk:toloul', itemCode: 'toloul', netKg: 2000),
        ],
      );
      final offer = dipOfferFromShipment(shipment);
      expect(offer, isNotNull);
      expect(offer!.lines, hasLength(1));
      expect(offer.lines.first.itemCode, 'toloul');
      expect(offer.lines.first.receivedQty, 7000);
    });

    test('IBC colour shipment yields no dip offer', () {
      const shipment = InkShipment(
        id: '51993-B',
        orderNumber: '51993',
        containerLetter: 'B',
        packagingMode: 'ibc',
        status: InkShipmentStatus.received,
        receivedUnits: [
          InkReceivedUnit(ref: '12345678', itemCode: 'yellow', netKg: 1000),
          InkReceivedUnit(ref: '12345679', itemCode: 'red', netKg: 1000),
        ],
      );
      expect(dipOfferFromShipment(shipment), isNull);
    });
  });

  group('dipOfferFromLocalOrder', () {
    test('toloul local PO offers dip with received estimate', () {
      const order = InkPurchaseOrder(
        id: 'po1',
        pulseRef: 'L-12',
        supplierName: 'Local',
        status: InkPurchaseOrderStatus.fulfilled,
        remainingKgByItem: {'toloul': 0},
        lines: [
          InkPurchaseOrderLine(
            itemCode: 'toloul',
            displayName: 'Toloul',
            unit: 'LTS',
            finalKg: 8000,
          ),
        ],
        track: InkPurchaseOrderTrack.local,
      );
      final offer = dipOfferFromLocalOrder(order);
      expect(offer, isNotNull);
      expect(offer!.lines.single.itemCode, 'toloul');
      expect(offer.lines.single.receivedQty, 8000);
    });
  });
}
