import 'package:ctp_job_cards/models/job_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JobStatusExtension.fromString', () {
    test('round-trips enum names', () {
      for (final s in JobStatus.values) {
        expect(JobStatusExtension.fromString(s.name), s);
      }
    });

    test('accepts display and legacy forms (Pulse-aligned)', () {
      expect(JobStatusExtension.fromString('Open'), JobStatus.open);
      expect(JobStatusExtension.fromString('In Progress'), JobStatus.inProgress);
      expect(JobStatusExtension.fromString('in progress'), JobStatus.inProgress);
      expect(JobStatusExtension.fromString('Monitoring'), JobStatus.monitor);
      expect(JobStatusExtension.fromString('monitor'), JobStatus.monitor);
      expect(JobStatusExtension.fromString('Closed'), JobStatus.closed);
      expect(JobStatusExtension.fromString('completed'), JobStatus.closed);
    });

    test('empty and unknown default to open', () {
      expect(JobStatusExtension.fromString(''), JobStatus.open);
      expect(JobStatusExtension.fromString('  '), JobStatus.open);
      expect(JobStatusExtension.fromString('garbage'), JobStatus.open);
    });
  });
}
