import 'package:ctp_job_cards/services/security_receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const categories = [
    'Parking',
    'Escort',
    'Fuel',
    'Maintenance',
    'Toll',
    'Fine',
    'Other',
    'Petrol',
    'Car wash',
    'Service',
  ];

  final fixedNow = DateTime(2026, 7, 15);

  group('SecurityReceiptParser amount', () {
    test('prefers TOTAL line over line items', () {
      const text = '''
ENGEN MIDDELBURG
ULP 95          45.20
OIL             89.00
SUBTOTAL       134.20
VAT             20.13
TOTAL          R 154.33
THANK YOU
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.amountZar, closeTo(154.33, 0.001));
      expect(r.confidence, greaterThanOrEqualTo(0.85));
      expect(r.suggestedCategory, anyOf('Fuel', 'Petrol'));
    });

    test('reads Afrikaans TOTAAL', () {
      const text = '''
SASOL GARAGE
PETROL 93
TOTAAL    R 502,50
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.amountZar, closeTo(502.50, 0.001));
    });

    test('amount on next line after TOTAL', () {
      const text = '''
SHELL
TOTAL
R 89.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.amountZar, closeTo(89.00, 0.001));
    });

    test('fallback uses largest late amount when no TOTAL keyword', () {
      const text = '''
QUICK MART
COFFEE    25.00
SNACK     15.00
          40.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.amountZar, closeTo(40.00, 0.001));
      expect(r.confidence, lessThan(0.85));
    });
  });

  group('SecurityReceiptParser date', () {
    test('parses SA DD/MM/YYYY near header', () {
      const text = '''
ENGEN
Date: 03/07/2026
TOTAL R 200.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.costDate, DateTime(2026, 7, 3));
    });

    test('parses ISO date', () {
      const text = '''
BP
2026-06-20 14:22
TOTAL 99.99
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.costDate, DateTime(2026, 6, 20));
    });

    test('rejects dates outside last year window', () {
      const text = '''
SHOP
01/01/2020
TOTAL R 10.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.costDate, isNull);
    });
  });

  group('SecurityReceiptParser description + category', () {
    test('merchant from known brand', () {
      const text = '''
SHELL ULTRA CITY N4
TOTAL R 850.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.description, contains('SHELL'));
      expect(r.suggestedCategory, anyOf('Fuel', 'Petrol'));
    });

    test('toll category', () {
      const text = '''
SANRAL TOLL PLAZA
TOTAL R 62.00
Date 12/07/2026
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.suggestedCategory, 'Toll');
      expect(r.amountZar, closeTo(62.00, 0.001));
    });

    test('parking category', () {
      const text = '''
CITY PARKADE
PARKING FEES
TOTAL R 35.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.suggestedCategory, 'Parking');
    });

    test('car wash maps to settings label', () {
      const text = '''
SUPER CAR WASH
TOTAL R 80.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: categories,
        now: fixedNow,
      );
      expect(r.suggestedCategory, 'Car wash');
    });

    test('never invents category not in settings list', () {
      const text = '''
ENGEN DIESEL
TOTAL R 100.00
''';
      final r = SecurityReceiptParser.parse(
        text,
        categories: const ['Parking', 'Toll'],
        now: fixedNow,
      );
      expect(r.suggestedCategory, isNull);
      expect(r.amountZar, closeTo(100.00, 0.001));
    });

    test('empty text', () {
      final r = SecurityReceiptParser.parse('', categories: categories);
      expect(r.hasUsableFields, isFalse);
      expect(r.amountZar, isNull);
    });
  });
}
