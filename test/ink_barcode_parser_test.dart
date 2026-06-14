import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/services/ink_barcode_parser.dart';

void main() {
  group('main label (GS1 + SSCC)', () {
    test('image 1: GS1 gives weight+charge, SSCC gives IBC number', () {
      // (01)04045647007179 (10)0014836440 (3100)000940  +  (00)340456470051031001
      final r = parseIbcBarcodes([
        '01040456470071791000148364403100000940', // GS1: 01+GTIN+10+charge+3100+weight
        '00340456470051031001',
      ]);
      expect(r.ibcNumber, '51031001'); // right 8 of the SSCC
      expect(r.weightKg, 940);
      expect(r.charge, '0014836440');
      expect(r.weightTruncated, isFalse);
      // No product/article code on the main label → colour stays null.
      expect(r.colour, isNull);
    });

    test('image 2: GS1 + bare 18-digit NVE', () {
      final r = parseIbcBarcodes([
        '0104045647007407100014816743 3100 000997'.replaceAll(' ', ''),
        '340456470050815480', // bare NVE (18 digits)
      ]);
      expect(r.ibcNumber, '50815480');
      expect(r.weightKg, 997);
      expect(r.charge, '0014816743');
    });
  });

  group('three-codes path', () {
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

    test('colour detection for each ink', () {
      expect(parseIbcBarcodes(['x123024622']).colour, 'Yellow');
      expect(parseIbcBarcodes(['x128049871']).colour, 'Red');
      expect(parseIbcBarcodes(['x121218796']).colour, 'Blue');
      expect(parseIbcBarcodes(['x129097382']).colour, 'Black');
    });
  });

  group('robustness', () {
    test('strips FNC1 / control chars and spaces', () {
      final r = parseIbcBarcodes(['01040456470071791000148364403100000940']);
      expect(r.weightKg, 940);
      expect(r.charge, '0014836440');
    });

    test('truncated/partial 3100 weight is flagged', () {
      // Only 4 weight digits scanned.
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
