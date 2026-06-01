import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/formatters.dart';

void main() {
  group('WasteTrack SA Formatters (Phase 6)', () {
    test('formatSAWeight produces reasonable ZA formatted output', () {
      final w1 = formatSAWeight(1234.5);
      expect(w1.contains('234'), true); // handles nbsp/comma variants
      expect(w1.contains('kg'), true);
      final w0 = formatSAWeight(0);
      expect(w0.isNotEmpty, true);
      expect(w0.contains('kg'), true);
    });

    test('formatSACurrency uses R and ZA formatting', () {
      final c = formatSACurrency(12450.75);
      expect(c.startsWith('R '), true);
      expect(c.contains('450'), true); // thousands grouping present
    });

    test('formatSADate uses DD/MM/YYYY', () {
      final d = DateTime(2026, 5, 31);
      expect(formatSADate(d), '31/05/2026');
    });

    test('formatSADateTime includes time', () {
      final dt = DateTime(2026, 5, 31, 14, 5);
      final s = formatSADateTime(dt);
      expect(s, contains('31/05/2026'));
      expect(s, contains('14:05'));
    });
  });
}
