import 'package:ctp_job_cards/services/ink_delivery_note_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InkDeliveryNoteParser', () {
    test('reads WL number on same line as Delivery Note', () {
      const text = '''
Siyaya Local And Crossborder (Pty) Ltd
Delivery Note                    WL817898
Customer Reference Number - SD3651266946
Operator - MAERSK
Vessel - SANTA URSULA / 633S /
Container Number - MRSU 0460664
''';
      final r = InkDeliveryNoteParser.parse(text);
      expect(r.noteNumber, 'WL817898');
      expect(r.confidence, greaterThanOrEqualTo(0.9));
      expect(r.hasCandidate, isTrue);
    });

    test('reads number on next line after Delivery Note label', () {
      const text = '''
DELIVERY NOTE
WL817898
Customer Reference Number
SD3651266946
''';
      final r = InkDeliveryNoteParser.parse(text);
      expect(r.noteNumber, 'WL817898');
      expect(r.hasCandidate, isTrue);
    });

    test('ignores customer reference SD… and container MRSU…', () {
      const text = '''
Some header
Customer Reference Number - SD3651266946
Container Number - MRSU0460664
Vessel SANTA URSULA
No delivery label here
''';
      final r = InkDeliveryNoteParser.parse(text);
      expect(r.noteNumber, isNot(equals('SD3651266946')));
      expect(r.noteNumber, isNot(equals('MRSU0460664')));
    });

    test('DeliveryNote without space still works', () {
      const text = 'DeliveryNote WL912345\nProcessed By Clint';
      final r = InkDeliveryNoteParser.parse(text);
      expect(r.noteNumber, 'WL912345');
    });

    test('empty text returns no candidate', () {
      final r = InkDeliveryNoteParser.parse('   ');
      expect(r.hasCandidate, isFalse);
      expect(r.noteNumber, isNull);
    });

    test('header letter-digit still found without perfect label', () {
      const text = '''
Siyaya form
WL817898
Date 13/07/26
''';
      final r = InkDeliveryNoteParser.parse(text);
      expect(r.noteNumber, 'WL817898');
      expect(r.confidence, lessThan(0.9));
    });
  });
}
