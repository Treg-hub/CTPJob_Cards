import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/waste_type.dart';
import 'package:ctp_job_cards/utils/waste_stock_mapping.dart';

void main() {
  group('restrictToScheduledTypes (manager schedule restriction, Begin Collection)', () {
    final paper = const WasteType(id: 'p1', mainType: 'Paper Waste');
    final general = const WasteType(id: 'g1', mainType: 'General Waste');
    final hazardous = const WasteType(id: 'h1', mainType: 'Hazardous Waste');
    final contractorTypes = [paper, general, hazardous];

    test('empty selectedWasteTypes falls back to the full contractor list (legacy / unrestricted loads)', () {
      final result = restrictToScheduledTypes(contractorTypes, const []);
      expect(result, contractorTypes);
    });

    test('non-empty selectedWasteTypes restricts to only the matching mainType names', () {
      final result = restrictToScheduledTypes(contractorTypes, const ['Paper Waste', 'General Waste']);
      expect(result.map((t) => t.mainType).toSet(), {'Paper Waste', 'General Waste'});
      expect(result, isNot(contains(hazardous)));
    });

    test('selectedWasteTypes naming a type not present in contractorTypes yields no match for that name', () {
      final result = restrictToScheduledTypes(contractorTypes, const ['Paper Waste', 'Not A Real Type']);
      expect(result.map((t) => t.mainType).toSet(), {'Paper Waste'});
    });

    test('selectedWasteTypes with no overlap at all returns an empty list (not a silent fallback to everything)', () {
      final result = restrictToScheduledTypes(contractorTypes, const ['Not A Real Type']);
      expect(result, isEmpty);
    });

    test('composes correctly with existing paper-family chip-merging logic (stockSubtypeFilterForChips)', () {
      // Manager scheduled only Paper Waste — guard's stock-link filter should
      // still expand to the full paper-family subtype set via the existing
      // paper-family logic, scoped to just the restricted chip.
      final restricted = restrictToScheduledTypes(contractorTypes, const ['Paper Waste']);
      expect(restricted, [paper]);

      final filter = stockSubtypeFilterForChips(restricted, contractorTypes);
      expect(filter, paperStockSubtypes(contractorTypes));
    });

    test('itemSubtypeOptionsForChips over a restricted list only offers the restricted types', () {
      final restricted = restrictToScheduledTypes(contractorTypes, const ['General Waste']);
      final options = itemSubtypeOptionsForChips(restricted, contractorTypes);
      expect(options, ['General Waste']);
    });
  });
}
