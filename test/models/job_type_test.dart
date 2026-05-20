import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/job_card.dart';

void main() {
  group('JobType.fromString', () {
    test('round-trips every enum via name (case-sensitive fast path)', () {
      for (final t in JobType.values) {
        expect(JobType.fromString(t.name), t, reason: 'round-trip failed for ${t.name}');
      }
    });

    test('parses camelCase mechanicalElectrical correctly (regression for the Mech/Elec corruption bug)', () {
      expect(JobType.fromString('mechanicalElectrical'), JobType.mechanicalElectrical);
    });

    test('accepts legacy display-name forms', () {
      expect(JobType.fromString('Mechanical'), JobType.mechanical);
      expect(JobType.fromString('Electrical'), JobType.electrical);
      expect(JobType.fromString('Mech/Elec'), JobType.mechanicalElectrical);
      expect(JobType.fromString('Mech/Elec ?'), JobType.mechanicalElectrical);
      expect(JobType.fromString('MechElec'), JobType.mechanicalElectrical);
      expect(JobType.fromString('mechanicalelectrical'), JobType.mechanicalElectrical);
      expect(JobType.fromString('Maintenance'), JobType.maintenance);
    });

    test('falls back to mechanical for empty or unknown values', () {
      expect(JobType.fromString(''), JobType.mechanical);
      expect(JobType.fromString('garbage'), JobType.mechanical);
    });
  });
}
