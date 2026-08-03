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
    const WasteType(
      mainType: 'Copper Skins',
      isFixedTareDualBin: true,
      quantityLabels: {'default': 'Quantity (bins)'},
    ),
    const WasteType(mainType: 'Compactor Bin', noSiteWeight: true),
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

    test('requires weighbridge for copper skins dual-bin', () {
      expect(
        loadSkipsWeighbridge(mainWasteType: 'Copper Skins', allTypes: types),
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

  group('mainTypeIsFixedTareDualBin', () {
    test('true for Copper Skins', () {
      expect(mainTypeIsFixedTareDualBin('Copper Skins', types), isTrue);
    });

    test('false for paper and no-site-weight', () {
      expect(mainTypeIsFixedTareDualBin('Paper Waste', types), isFalse);
      expect(mainTypeIsFixedTareDualBin('Compactor Bin', types), isFalse);
    });
  });

  group('copperSkinsNetKg', () {
    test('computes net from two grosses and two tares', () {
      expect(
        copperSkinsNetKg(
          grossBin1Kg: 400,
          grossBin2Kg: 450,
          tareBin1Kg: 120,
          tareBin2Kg: 135,
        ),
        595,
      );
    });

    test('returns null when net non-positive', () {
      expect(
        copperSkinsNetKg(
          grossBin1Kg: 100,
          grossBin2Kg: 100,
          tareBin1Kg: 120,
          tareBin2Kg: 135,
        ),
        isNull,
      );
    });

    test('returns null when tare missing or zero', () {
      expect(
        copperSkinsNetKg(
          grossBin1Kg: 400,
          grossBin2Kg: 450,
          tareBin1Kg: 0,
          tareBin2Kg: 135,
        ),
        isNull,
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

    test('includes fixed dual-bin net weight', () {
      final total = sumRecordedWeightKg([
        {
          'weight_kg': 595.0,
          'is_fixed_tare_dual_bin': true,
          'gross_bin1_kg': 400,
          'gross_bin2_kg': 450,
          'tare_bin1_kg': 120,
          'tare_bin2_kg': 135,
        },
      ]);
      expect(total, 595.0);
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

    test('uses net weight for dual-bin skins', () {
      const item = WasteItem(
        loadId: 'x',
        subtype: 'Copper Skins',
        weightKg: 595,
        quantity: 2,
        isFixedTareDualBin: true,
        ratePerKg: 80,
      );
      expect(itemLineValue(item, 80), 595 * 80);
    });
  });
}
