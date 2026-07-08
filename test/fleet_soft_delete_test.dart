import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/fleet_soft_delete.dart';

void main() {
  group('parseFleetDeleted', () {
    test('false when absent', () {
      expect(parseFleetDeleted({}), isFalse);
      expect(parseFleetDeleted(null), isFalse);
    });

    test('true only when explicitly true', () {
      expect(parseFleetDeleted({'is_deleted': true}), isTrue);
      expect(parseFleetDeleted({'is_deleted': false}), isFalse);
    });
  });
}