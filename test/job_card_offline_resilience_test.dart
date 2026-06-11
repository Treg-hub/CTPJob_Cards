// Regression tests for the job-card data-corruption bugs found in the
// 2026-06 review:
//  - offline queue replays wrote ISO-8601 strings into Timestamp fields,
//    corrupting the doc and crashing JobCard.fromFirestore for every user;
//  - the Cloud Function specialist auto-assign wrote assignmentHistory in a
//    shape AssignmentEvent.fromFirestore couldn't parse;
//  - one bad doc poisoned the entire stream emission for every list screen.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/models/assignment_event.dart';
import 'package:ctp_job_cards/models/job_card.dart';
import 'package:ctp_job_cards/services/firestore_service.dart';
import 'package:ctp_job_cards/services/sync_service.dart';

// Minimal DocumentSnapshot stand-in — JobCard.fromFirestore and
// FirestoreService.parseJobCards only touch `id` and `data()`.
// ignore: subtype_of_sealed_class
class FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  final String _id;
  final Map<String, dynamic>? _data;
  FakeDoc(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  group('sanitize → restore round trip (offline replay)', () {
    test('queued job-card update payload restores all Timestamp fields', () {
      final now = DateTime(2026, 6, 1, 8, 30);
      final card = JobCard(
        id: 'job1',
        jobCardNumber: 101,
        department: 'Press',
        area: 'Line 1',
        machine: 'Press 4',
        part: 'Motor',
        type: JobType.mechanical,
        priority: 4,
        operator: 'Op Name',
        operatorClockNo: '77',
        assignedClockNos: const ['12'],
        assignedNames: const ['Tech A'],
        description: 'Motor tripping',
        status: JobStatus.inProgress,
        createdAt: now,
        assignedAt: now,
        startedAt: now,
        completedAt: null,
        assignmentHistory: [
          AssignmentEvent(
            assignedByName: 'Tech A',
            assignedByClockNo: '12',
            assigneeClockNos: const ['12'],
            assigneeNames: const ['Tech A'],
            timestamp: now,
          ),
        ],
      );

      // What addToQueue stores in Hive…
      final sanitized =
          SyncService.sanitizeForHive(card.toFirestore(includePhotos: false));
      // Timestamps must have become strings (Hive can't store them)…
      expect(sanitized['createdAt'], isA<String>());
      expect(
          (sanitized['assignmentHistory'] as List).first['timestamp'], isA<String>());

      // …and what replay writes back must be Firestore types again.
      final restored = SyncService.restoreJobCardTimestamps(sanitized);
      expect(restored['createdAt'], isA<Timestamp>());
      expect(restored['assignedAt'], isA<Timestamp>());
      expect(restored['startedAt'], isA<Timestamp>());
      expect((restored['createdAt'] as Timestamp).toDate(), now);
      // lastUpdatedAt means "when this landed" → serverTimestamp sentinel.
      expect(restored['lastUpdatedAt'], isA<FieldValue>());
      final history = restored['assignmentHistory'] as List;
      expect((history.first as Map)['timestamp'], isA<Timestamp>());
      // Nulls stay null, no strings survive anywhere in the timestamp fields.
      expect(restored['completedAt'], isNull);
    });
  });

  group('JobCard.fromFirestore tolerance', () {
    test('parses string timestamps (corrupted docs) instead of throwing', () {
      final card = JobCard.fromFirestore(FakeDoc('d1', {
        'department': 'Press',
        'status': 'closed',
        'createdAt': '2026-05-01T08:00:00.000',
        'completedAt': '2026-05-02T10:15:00.000',
        'closedAt': Timestamp.fromDate(DateTime(2026, 5, 2)),
      }));
      expect(card.createdAt, DateTime(2026, 5, 1, 8));
      expect(card.completedAt, DateTime(2026, 5, 2, 10, 15));
      expect(card.closedAt, DateTime(2026, 5, 2));
      expect(card.status, JobStatus.closed);
    });

    test('parses scalar assignedClockNos/Names (legacy Assign Self damage)', () {
      final card = JobCard.fromFirestore(FakeDoc('d2', {
        'assignedClockNos': '12',
        'assignedNames': 'Tech A',
      }));
      expect(card.assignedClockNos, ['12']);
      expect(card.assignedNames, ['Tech A']);
    });

    test('skips CF-shaped history entries it cannot parse, keeps the rest', () {
      final good = AssignmentEvent(
        assignedByName: 'Mgr',
        assignedByClockNo: '1',
        assigneeClockNos: const ['12'],
        assigneeNames: const ['Tech A'],
        timestamp: DateTime(2026, 6, 1),
      ).toFirestore();

      final card = JobCard.fromFirestore(FakeDoc('d3', {
        'assignmentHistory': [
          good,
          // Legacy CF auto-assign shape — has assignedAt instead of timestamp.
          {
            'clockNo': '99',
            'name': 'Specialist',
            'assignedAt': Timestamp.fromDate(DateTime(2026, 6, 2)),
            'assignedBy': 'system',
            'assignedByName': 'Auto-assigned (Pre Press Specialist)',
          },
          // Total garbage — no recoverable timestamp at all.
          {'foo': 'bar'},
          'not even a map',
        ],
      }));

      expect(card.assignmentHistory.length, 2);
      expect(card.assignmentHistory[0].assigneeNames, ['Tech A']);
      // The CF shape is recovered, not dropped.
      expect(card.assignmentHistory[1].assigneeClockNos, ['99']);
      expect(card.assignmentHistory[1].timestamp, DateTime(2026, 6, 2));
    });

    test('empty doc parses with defaults', () {
      final card = JobCard.fromFirestore(FakeDoc('d4', {}));
      expect(card.status, JobStatus.open);
      expect(card.assignmentHistory, isEmpty);
      expect(card.createdAt, isNull);
    });
  });

  group('AssignmentEvent.tryFromFirestore', () {
    test('string timestamp is recovered', () {
      final e = AssignmentEvent.tryFromFirestore({
        'assignedByName': 'Tech A',
        'assignedByClockNo': '12',
        'assigneeClockNos': ['12'],
        'assigneeNames': ['Tech A'],
        'timestamp': '2026-06-01T07:00:00.000',
      });
      expect(e, isNotNull);
      expect(e!.timestamp, DateTime(2026, 6, 1, 7));
    });

    test('unrecoverable entry returns null', () {
      expect(AssignmentEvent.tryFromFirestore({'assignedByName': 'x'}), isNull);
    });
  });

  group('parseJobCards stream-poisoning protection', () {
    test('drops the bad doc, keeps the good ones', () {
      final docs = [
        FakeDoc('good1', {'department': 'Press', 'status': 'open'}),
        // jobCardNumber with the wrong runtime type still throws in the model —
        // exactly the class of doc that used to blank every list screen.
        FakeDoc('bad', {'jobCardNumber': 'not-a-number'}),
        FakeDoc('good2', {'department': 'Ink', 'status': 'closed'}),
      ];

      final cards = FirestoreService.parseJobCards(docs);
      expect(cards.length, 2);
      expect(cards.map((c) => c.id), ['good1', 'good2']);
    });
  });
}
