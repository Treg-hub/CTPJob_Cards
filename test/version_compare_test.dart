import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/version_compare.dart';

void main() {
  group('isNewerAppVersion', () {
    test('higher major is newer', () {
      expect(isNewerAppVersion('2.0.0', '3.0.0', '1', '1'), isTrue);
    });

    test('lower patch is not newer', () {
      expect(isNewerAppVersion('2.3.1', '2.3.0', '100', '99'), isFalse);
    });

    test('same version higher build is newer', () {
      expect(isNewerAppVersion('2.3.0', '2.3.0', '120', '130'), isTrue);
    });

    test('same version and build is not newer', () {
      expect(isNewerAppVersion('2.3.0', '2.3.0', '130', '130'), isFalse);
    });

    test('same version empty latest build is not newer', () {
      expect(isNewerAppVersion('2.3.0', '2.3.0', '130', ''), isFalse);
    });

    test('malformed version returns false', () {
      expect(isNewerAppVersion('abc', '2.0.0', '1', '2'), isFalse);
    });
  });
}
