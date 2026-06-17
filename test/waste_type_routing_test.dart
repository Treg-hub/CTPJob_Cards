import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/waste_item.dart';
import 'package:ctp_job_cards/models/waste_type.dart';
import 'package:ctp_job_cards/utils/waste_type_routing.dart';

void main() {
  final types = [
    const WasteType(mainType: 'Paper Waste', subtypes: ['Reelends']),
    const WasteType(
      mainType: 'IBC Bins',
      isQuantityOnly: true,
      quantityLabels: {'default': 'Quantity (bins)'},
    ),
    const WasteType(mainType: 'Copper Skins', noSiteWeight: true),
  ];

  group('loadSkipsWeighbridge', () {
    test('skips when main type is quantity-only', () {
      expect(
        loadSkipsWeighbridge(mainWasteType: 'IBC Bins', allTypes: types),
        isTrue,
      );
    });

    test('requires weighbridge for weight-based main type', () {
      expect(
        loadSkipsWeighbridge(mainWasteType: 'Paper Waste', allTypes: types),
        isFalse,
      );
    });

    test('skips when every item is quantity-only', () {
      expect(
        loadSkipsWeighbridge(
          mainWasteType: 'Paper Waste',
          allTypes: types,
          itemQuantityOnlyFlags: const [true, true],
        ),
        isTrue,
      );
    });
  });

  group('sumRecordedWeightKg', () {
    test('excludes quantity-only and no-site-weight items', () {
      final total = sumRecordedWeightKg([
        {'weight_kg': 100.0},
        {'weight_kg': 50.0, 'is_quantity_only': true},
        {'weight_kg': 0.0, 'is_no_site_weight': true, 'quantity': 2},
      ]);
      expect(total, 100.0);
    });
  });

  group('itemLineValue', () {
    test('uses quantity for quantity-only items', () {
      const item = WasteItem(
        loadId: 'x',
        subtype: 'IBC Bins',
        weightKg: 0,
        quantity: 3,
        isQuantityOnly: true,
        ratePerKg: 120,
      );
      expect(itemLineValue(item, 120), 360);
    });

    test('uses weight for weight-based items', () {
      const item = WasteItem(
        loadId: 'x',
        subtype: 'Reelends',
        weightKg: 250,
        ratePerKg: 3.5,
      );
      expect(itemLineValue(item, 3.5), 875);
    });
  });
}