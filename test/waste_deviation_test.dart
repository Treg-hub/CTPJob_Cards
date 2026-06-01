import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/deviation.dart';
import 'package:ctp_job_cards/services/waste_service.dart';

void main() {
  group('calculateDeviation (WasteTrack Phase 6)', () {
    test('returns no deviation when actual <= 0', () {
      final result = calculateDeviation(recordedWeightKg: 100, actualWeightKg: 0);
      expect(result.isDeviation, false);
      expect(result.varianceKg, 0);
    });

    test('detects deviation by percent > 5%', () {
      // recorded 100, actual 90 => ~11.1% variance
      final result = calculateDeviation(recordedWeightKg: 100, actualWeightKg: 90);
      expect(result.isDeviation, true);
      expect(result.variancePercent.abs(), greaterThan(5));
    });

    test('detects deviation by kg > 50', () {
      final result = calculateDeviation(recordedWeightKg: 100, actualWeightKg: 160);
      expect(result.isDeviation, true);
      expect(result.varianceKg.abs(), greaterThan(50));
    });

    test('no deviation within both thresholds', () {
      final result = calculateDeviation(recordedWeightKg: 100, actualWeightKg: 102);
      expect(result.isDeviation, false);
    });

    test('custom thresholds respected', () {
      final result = calculateDeviation(
        recordedWeightKg: 100,
        actualWeightKg: 108,
        thresholdPercent: 10,
        thresholdKg: 20,
      );
      expect(result.isDeviation, false); // 8% and 8kg within custom
    });
  });

  // Targeted unit test for signature offline queuing (pure API surface / logic stub, per PRD slice; full integration in widget/service tests)
  group('WasteService signature offline queuing (temp file pattern)', () {
    test('exposes sessionQueuedSignatureCount getter (pure accessor)', () {
      final service = WasteService(); // construction is pure
      expect(service.sessionQueuedSignatureCount, isA<int>());
      expect(service.sessionQueuedSignatureCount, 0);
    });
  });
}
