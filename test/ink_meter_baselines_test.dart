import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/ink_meter_baselines.dart';

void main() {
  group('latestNonVoidedMeterReadings', () {
    test('skips voided so void-and-re-enter uses prior baseline', () {
      final yesterday = DateTime(2026, 7, 12, 8);
      final todayVoided = DateTime(2026, 7, 13, 8);
      final latest = latestNonVoidedMeterReadings([
        (key: 'YEL', at: yesterday, reading: 1000, voided: false),
        (key: 'YEL', at: todayVoided, reading: 1120, voided: true),
      ]);
      expect(latest['YEL'], 1000);
    });

    test('keeps newest non-voided when later voided exists', () {
      final a = DateTime(2026, 7, 10);
      final b = DateTime(2026, 7, 11);
      final c = DateTime(2026, 7, 12);
      final latest = latestNonVoidedMeterReadings([
        (key: 'BLK', at: a, reading: 100, voided: false),
        (key: 'BLK', at: b, reading: 150, voided: false),
        (key: 'BLK', at: c, reading: 999, voided: true),
      ]);
      expect(latest['BLK'], 150);
    });

    test('omits key when only voided rows exist', () {
      final latest = latestNonVoidedMeterReadings([
        (key: 'RED', at: DateTime(2026, 7, 13), reading: 50, voided: true),
      ]);
      expect(latest.containsKey('RED'), isFalse);
    });
  });

  group('recentNonVoidedMeterReadings', () {
    test('excludes voided from history list', () {
      final recent = recentNonVoidedMeterReadings([
        (key: 'YEL', at: DateTime(2026, 7, 11), reading: 900, voided: false),
        (key: 'YEL', at: DateTime(2026, 7, 12), reading: 1000, voided: false),
        (key: 'YEL', at: DateTime(2026, 7, 13), reading: 1120, voided: true),
      ], limit: 4);
      expect(recent['YEL']!.map((e) => e.reading).toList(), [1000, 900]);
    });
  });
}
