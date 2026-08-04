import 'package:ctp_job_cards/models/ink_purchase_order.dart';
import 'package:ctp_job_cards/models/ink_shipment.dart';
import 'package:ctp_job_cards/utils/ink_expected_deliveries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed "now": 2026-08-04 10:00 UTC = 12:00 SAST.
  final now = DateTime.utc(2026, 8, 4, 10);

  group('sastDayKey', () {
    test('UTC evening still same SAST day before midnight', () {
      // 21:00 UTC = 23:00 SAST 4 Aug
      expect(sastDayKey(DateTime.utc(2026, 8, 4, 21)), '2026-08-04');
    });
    test('UTC late maps to next SAST day', () {
      // 22:30 UTC = 00:30 SAST 5 Aug
      expect(sastDayKey(DateTime.utc(2026, 8, 4, 22, 30)), '2026-08-05');
    });
  });

  group('etaInHorizon', () {
    test('includes overdue', () {
      final eta = DateTime.utc(2026, 7, 28, 12);
      expect(etaInHorizon(eta, now: now), isTrue);
      expect(daysUntilEta(eta, now: now), lessThan(0));
    });
    test('includes today', () {
      final eta = DateTime.utc(2026, 8, 4, 12);
      expect(etaInHorizon(eta, now: now), isTrue);
      expect(daysUntilEta(eta, now: now), 0);
    });
    test('includes day +5', () {
      final eta = DateTime.utc(2026, 8, 9, 12);
      expect(etaInHorizon(eta, now: now), isTrue);
      expect(daysUntilEta(eta, now: now), 5);
    });
    test('excludes day +6', () {
      final eta = DateTime.utc(2026, 8, 10, 12);
      expect(etaInHorizon(eta, now: now), isFalse);
      expect(daysUntilEta(eta, now: now), 6);
    });
  });

  group('urgency labels', () {
    test('overdue today tomorrow in N', () {
      expect(expectedUrgencyLabel(InkExpectedUrgency.overdue), 'overdue');
      expect(expectedUrgencyLabel(InkExpectedUrgency.today), 'today');
      expect(expectedUrgencyLabel(InkExpectedUrgency.tomorrow), 'tomorrow');
      expect(
        expectedUrgencyLabel(InkExpectedUrgency.inNDays, inDays: 3),
        'in 3 days',
      );
    });
  });

  group('buildExpectedDeliveries', () {
    InkPurchaseOrder localPo({
      required String id,
      required String pulseRef,
      required String supplier,
      required DateTime? eta,
      List<InkPurchaseOrderLine>? lines,
      Map<String, double>? remaining,
    }) {
      final ls = lines ??
          [
            const InkPurchaseOrderLine(
              itemCode: 'binder',
              displayName: 'Binder',
              unit: 'KG',
              finalKg: 500,
            ),
          ];
      return InkPurchaseOrder(
        id: id,
        pulseRef: pulseRef,
        supplierName: supplier,
        status: InkPurchaseOrderStatus.sent,
        remainingKgByItem: remaining ?? {'binder': 500},
        lines: ls,
        track: InkPurchaseOrderTrack.local,
        estimatedArrival: eta,
      );
    }

    InkShipment shipment({
      required String id,
      required DateTime? eta,
      String packagingMode = 'ibc',
    }) {
      return InkShipment(
        id: id,
        orderNumber: id.split('-').first,
        containerLetter: id.contains('-') ? id.split('-').last : 'A',
        packagingMode: packagingMode,
        status: InkShipmentStatus.awaitingReceipt,
        expectedArrival: eta,
        lines: const [
          InkShipmentLine(itemCode: 'yellow', expectedKg: 1000),
        ],
      );
    }

    test('local headline is supplier · products (no PO ref)', () {
      final po = localPo(
        id: '1',
        pulseRef: 'INK-PO-2026-0042',
        supplier: 'Acme Chemicals',
        eta: DateTime.utc(2026, 8, 4, 12),
      );
      final row = expectedFromLocalPo(po, now: now)!;
      expect(row.headline, 'Acme Chemicals · Binder');
      expect(row.refLabel, 'INK-PO-2026-0042');
      expect(row.headline.contains('INK-PO'), isFalse);
    });

    test('shipment uses id as headline', () {
      final s = shipment(
        id: '51993-K',
        eta: DateTime.utc(2026, 8, 5, 12),
      );
      final row = expectedFromShipment(s, now: now)!;
      expect(row.headline, '51993-K');
      expect(row.refLabel, '51993-K');
    });

    test('sort overdue then soonest; excludes far ETA and import POs', () {
      final list = buildExpectedDeliveries(
        now: now,
        localOrders: [
          localPo(
            id: 'far',
            pulseRef: 'PO-FAR',
            supplier: 'Far Co',
            eta: DateTime.utc(2026, 8, 20, 12),
          ),
          localPo(
            id: 'soon',
            pulseRef: 'PO-SOON',
            supplier: 'Soon Co',
            eta: DateTime.utc(2026, 8, 7, 12),
          ),
          localPo(
            id: 'late',
            pulseRef: 'PO-LATE',
            supplier: 'Late Co',
            eta: DateTime.utc(2026, 7, 30, 12),
          ),
          InkPurchaseOrder(
            id: 'imp',
            pulseRef: 'PO-IMP',
            supplierName: 'Siegwerk',
            status: InkPurchaseOrderStatus.sent,
            remainingKgByItem: const {'yellow': 1000},
            track: InkPurchaseOrderTrack.importTrack,
            estimatedArrival: DateTime.utc(2026, 8, 4, 12),
          ),
        ],
        shipments: [
          shipment(id: '51993-K', eta: DateTime.utc(2026, 8, 5, 12)),
          shipment(
            id: '51994-A',
            eta: DateTime.utc(2026, 8, 6, 12),
            packagingMode: 'pallet',
          ),
          shipment(id: 'no-eta', eta: null),
        ],
      );
      expect(
        list.map((e) => e.id).toList(),
        ['late', '51993-K', '51994-A', 'soon'],
      );
      expect(list.first.urgency, InkExpectedUrgency.overdue);
      expect(list[1].kind, InkExpectedKind.shipment);
      expect(list[2].isPalletShipment, isTrue);
      expect(list[2].packagingMode, 'pallet');
    });
  });
}
