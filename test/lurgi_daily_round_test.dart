import 'package:ctp_job_cards/models/lurgi_chemical_usage.dart';
import 'package:ctp_job_cards/models/lurgi_daily_round.dart';
import 'package:ctp_job_cards/models/lurgi_recycling_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lurgiDateKey', () {
    test('formats local calendar day', () {
      expect(lurgiDateKey(DateTime(2026, 7, 18)), '2026-07-18');
      expect(lurgiDateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('lurgiMeterDelta', () {
    test('null previous yields null unless reset', () {
      expect(lurgiMeterDelta(null, 10), isNull);
      expect(lurgiMeterDelta(null, 10, reset: true), 10);
    });

    test('subtracts previous', () {
      expect(lurgiMeterDelta(100, 115), 15);
    });

    test('reset uses current as full span', () {
      expect(lurgiMeterDelta(999, 12, reset: true), 12);
    });
  });

  group('lurgiDateKeyDaySpan', () {
    test('counts calendar days between keys', () {
      expect(lurgiDateKeyDaySpan('2026-07-15', '2026-07-18'), 3);
      expect(lurgiDateKeyDaySpan('2026-07-18', '2026-07-18'), 0);
    });
  });

  group('lurgiYesterdayDateKey', () {
    test('returns previous calendar day', () {
      expect(lurgiYesterdayDateKey(DateTime(2026, 7, 18)), '2026-07-17');
    });
  });

  group('LurgiDailyRound completion', () {
    test('morningComplete requires all five sections', () {
      final partial = LurgiDailyRound(
        dateKey: '2026-07-18',
        gasMechanical: 1,
        gasElectrical: 2,
        boilerFeed: 3,
        softener: 4,
      );
      expect(partial.utilitiesComplete, isTrue);
      expect(partial.morningComplete, isFalse);
      expect(partial.completedSectionCount, 1);

      final full = LurgiDailyRound(
        dateKey: '2026-07-18',
        gasMechanical: 1,
        gasElectrical: 2,
        boilerFeed: 3,
        softener: 4,
        freshWater: 10,
        effluent: 5,
        airMeter1: 1,
        airMeter2: 2,
        geyserTemp: 60,
        tank1Litres: 100,
        tank1Direction: 'in',
        tank2Litres: 200,
        tank2Direction: 'out',
        tank3Litres: 50,
        tank3Direction: 'in',
      );
      expect(full.morningComplete, isTrue);
      expect(full.completedSectionCount, LurgiDailyRound.totalSections);
    });
  });

  group('Phase 2 day totals', () {
    test('chemical totals sum entries', () {
      final a = LurgiChemicalUsage(
        dateKey: '2026-07-18',
        recordedAt: DateTime(2026, 7, 18, 8),
        causticSodaKg: 5,
        hydrochloricAcidKg: 1,
        actorClockNo: '1',
        actorName: 'A',
      );
      final b = LurgiChemicalUsage(
        dateKey: '2026-07-18',
        recordedAt: DateTime(2026, 7, 18, 12),
        sodiumChlorideKg: 2,
        naccolaintKg: 0.5,
        actorClockNo: '1',
        actorName: 'A',
      );
      final t = LurgiChemicalDayTotals.fromEntries([a, b]);
      expect(t.entryCount, 2);
      expect(t.causticSodaKg, 5);
      expect(t.hydrochloricAcidKg, 1);
      expect(t.sodiumChlorideKg, 2);
      expect(t.naccolaintKg, 0.5);
      expect(t.totalKg, 8.5);
    });

    test('recycling summary sums litres', () {
      final runs = [
        LurgiRecyclingRun(
          dateKey: '2026-07-18',
          startAt: DateTime(2026, 7, 18, 6),
          finishAt: DateTime(2026, 7, 18, 8),
          steamTemp: 100,
          steamPress: 2,
          litresRecycled: 200,
          dirtyToloulLevelLitres: 50,
          machineCleaned: true,
          actorClockNo: '1',
          actorName: 'A',
        ),
        LurgiRecyclingRun(
          dateKey: '2026-07-18',
          startAt: DateTime(2026, 7, 18, 10),
          finishAt: DateTime(2026, 7, 18, 12),
          steamTemp: 100,
          steamPress: 2,
          litresRecycled: 150,
          dirtyToloulLevelLitres: 20,
          machineCleaned: false,
          actorClockNo: '1',
          actorName: 'A',
        ),
      ];
      final s = LurgiRecyclingDaySummary.fromRuns(runs);
      expect(s.runCount, 2);
      expect(s.totalLitresRecycled, 350);
    });
  });
}
