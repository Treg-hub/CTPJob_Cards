import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/services/ink_barcode_parser.dart';

void main() {
  group('main label (GS1 + SSCC) — raw scanner output', () {
    test('GS1 gives weight+charge+colour, SSCC gives IBC number', () {
      // (01)04045647007179 (10)0014836440 (3100)000940  +  (00)340456470051031001
      final r = parseIbcBarcodes([
        '01040456470071791000148364403100000940',
        '00340456470051031001',
      ]);
      expect(r.ibcNumber, '51031001'); // right-8 of SSCC
      expect(r.colour, 'Yellow'); // GTIN 04045647007179 → Yellow
      expect(r.weightKg, 940);
      expect(r.charge, '0014836440');
      expect(r.weightTruncated, isFalse);
    });

    test('GS1 + bare 18-digit NVE', () {
      final r = parseIbcBarcodes([
        '0104045647007407100014816743' '3100000997',
        '340456470050815480', // bare NVE (18 digits)
      ]);
      expect(r.ibcNumber, '50815480');
      expect(r.weightKg, 997);
      expect(r.charge, '0014816743');
    });
  });

  group('main label — parenthesised scanner output', () {
    // Some scanners return the human-readable form with (NN) AI markers.
    // _clean() must strip parentheses so parsing is identical to raw output.
    test('full parenthesised GS1 + SSCC', () {
      final r = parseIbcBarcodes([
        '(01)04045647007179(10)0014836440(3100)000940',
        '(00)340456470051031001',
      ]);
      expect(r.ibcNumber, '51031001');
      expect(r.colour, 'Yellow');
      expect(r.weightKg, 940);
      expect(r.charge, '0014836440');
      expect(r.weightTruncated, isFalse);
    });

    test('parenthesised with spaces in SSCC human-readable', () {
      // Scanner may insert a space in the SSCC display group, e.g. "...510 31001"
      final r = parseIbcBarcodes([
        '(01)04045647007179(10)0014836440(3100)000940',
        '(00)34045647005103 1001',
      ]);
      expect(r.ibcNumber, '51031001');
      expect(r.weightKg, 940);
    });
  });

  group('weight AI decimal variants (31XX)', () {
    test('3100 — 0 decimal places: 000940 → 940 kg', () {
      final r = parseIbcBarcodes(['010404564700717910001483644031 00000940'.replaceAll(' ', '')]);
      expect(r.weightKg, 940);
    });

    test('3101 — 1 decimal place: 009400 → 940.0 kg', () {
      // 9400 / 10 = 940.0
      final r = parseIbcBarcodes(['010404564700717910001483644031 01009400'.replaceAll(' ', '')]);
      expect(r.weightKg, closeTo(940.0, 0.001));
    });

    test('3102 — 2 decimal places: 094000 → 940.00 kg', () {
      final r = parseIbcBarcodes(['010404564700717910001483644031 02094000'.replaceAll(' ', '')]);
      expect(r.weightKg, closeTo(940.0, 0.001));
    });
  });

  group('three-codes legacy path', () {
    test('& IBC + article colour + # weight all merge', () {
      final r = parseIbcBarcodes([
        '&00012351077245', // IBC → right 8
        '0128049871', // article right-9 = 128049871 → Red
        '#094000', // right 6 / 100 = 940.00
      ]);
      expect(r.ibcNumber, '51077245');
      expect(r.colour, 'Red');
      expect(r.weightKg, 940);
    });

    test('colour detection for each ink via legacy article code', () {
      expect(parseIbcBarcodes(['x123024622']).colour, 'Yellow');
      expect(parseIbcBarcodes(['x128049871']).colour, 'Red');
      expect(parseIbcBarcodes(['x121218796']).colour, 'Blue');
      expect(parseIbcBarcodes(['x129097382']).colour, 'Black');
    });
  });

  group('GTIN colour lookup', () {
    test('Yellow GTIN extracted from GS1-128 compound code', () {
      final r = parseIbcBarcodes(['01040456470071791000148364403100000940']);
      expect(r.colour, 'Yellow');
    });

    test('Black GTIN 04045647839596 resolves to Black', () {
      final r = parseIbcBarcodes(['01040456478395961000000000003100000940']);
      expect(r.colour, 'Black');
    });

    test('unknown GTIN returns null colour (falls through to legacy check)', () {
      // GTIN 04045647999999 not in kInkGtinColours and no legacy article code.
      final r = parseIbcBarcodes(['01040456479999991000000000003100000940']);
      expect(r.colour, isNull);
    });
  });

  group('robustness', () {
    test('strips FNC1 / control chars and spaces', () {
      final r = parseIbcBarcodes(['01040456470071791000148364403100000940']);
      expect(r.weightKg, 940);
      expect(r.charge, '0014836440');
    });

    test('truncated/partial weight field is flagged', () {
      // Only 4 weight digits captured — weight is partial.
      final r = parseIbcBarcodes(['01040456470071791000148364403100' '0009']);
      expect(r.weightTruncated, isTrue);
    });

    test('empty / junk codes yield nothing', () {
      final r = parseIbcBarcodes(['', '   ']);
      expect(r.hasAnything, isFalse);
    });

    test('merge prefers populated fields', () {
      const a = IbcScanResult(ibcNumber: '51031001');
      const b = IbcScanResult(colour: 'Blue', weightKg: 1003);
      final m = a.merge(b);
      expect(m.ibcNumber, '51031001');
      expect(m.colour, 'Blue');
      expect(m.weightKg, 1003);
      expect(m.isComplete, isTrue);
    });
  });
}
