import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/waste_stock_item.dart';
import 'package:ctp_job_cards/utils/waste_stock_snapshot.dart';

void main() {
  group('WasteStockSnapshot', () {
    test('fromItem and eligibleForQueue round-trip selected ids', () {
      final stock = WasteStockItem(
        id: 'stock-1',
        wasteType: 'Paper Waste',
        subtype: 'Mixed paper',
        photos: ['https://example.com/a.jpg'],
        estimatedWeightKg: 42,
        quantity: 2,
        status: WasteStockStatus.onSite,
        createdBy: '22',
        createdByName: 'Guard',
        createdAt: DateTime(2026, 7, 6),
      );
      final snap = WasteStockSnapshot.fromItem(stock);
      final eligible = WasteStockSnapshot.eligibleForQueue(
        ['stock-1', 'missing'],
        [snap],
      );
      expect(eligible, hasLength(1));
      expect(eligible.first['id'], 'stock-1');
      expect(WasteStockSnapshot.label(eligible.first), 'Mixed paper');
      expect(WasteStockSnapshot.weightKg(eligible.first), 42);
      expect(WasteStockSnapshot.photos(eligible.first), ['https://example.com/a.jpg']);
    });

    test('eligibleForQueue skips loaded or deleted stock', () {
      final eligible = WasteStockSnapshot.eligibleForQueue(
        ['a', 'b'],
        [
          {'id': 'a', 'status': 'loaded', 'is_deleted': false},
          {'id': 'b', 'status': 'on_site', 'is_deleted': true},
        ],
      );
      expect(eligible, isEmpty);
    });
  });
}