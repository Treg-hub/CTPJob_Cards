import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/formatters.dart';

void main() {
  group('titleCaseWords', () {
    test('capitalizes single word', () {
      expect(titleCaseWords('pump'), 'Pump');
    });

    test('capitalizes multi-word part names', () {
      expect(titleCaseWords('pump seal'), 'Pump Seal');
      expect(titleCaseWords('  drive belt  '), 'Drive Belt');
    });

    test('preserves all-caps acronyms', () {
      expect(titleCaseWords('IBC pump'), 'IBC Pump');
      expect(titleCaseWords('SKU'), 'SKU');
    });

    test('handles empty and mixed case', () {
      expect(titleCaseWords(''), '');
      expect(titleCaseWords('   '), '');
      expect(titleCaseWords('pUMP'), 'Pump');
    });
  });
}
