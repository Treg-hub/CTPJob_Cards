import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ctp_job_cards/constants/collections.dart';
import 'package:ctp_job_cards/models/sync_queue_item.dart';
import 'package:ctp_job_cards/services/fleet_service.dart';
import 'package:ctp_job_cards/services/sync_service.dart';

/// Fleet offline-integrity tests — the queue bookkeeping that prevents:
///   1. duplicate FM work records when a post-CF step fails or the app is
///      force-closed before the queue entry is removed,
///   2. queue replays overwriting a live issue doc (reverting status/photos),
///   3. duplicate photo uploads from stale or double-queued photo entries.
///
/// Uses the same harness pattern as waste_offline_resilience_test.dart:
/// real SyncService + Hive in a temp dir, no Firebase app. processNow() is
/// wrapped in try/catch where it would hit Firestore — the queue bookkeeping
/// under test runs before (dedupe) or independently of (mutate/remove) the
/// network calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('fleet_offline_resilience_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(SyncQueueItemAdapter());
    }

    if (Hive.isBoxOpen('sync_queue')) {
      await Hive.box<SyncQueueItem>('sync_queue').close();
    }
    await Hive.openBox<SyncQueueItem>('sync_queue');

    await SyncService().init();
  });

  tearDownAll(() async {
    try {
      if (Hive.isBoxOpen('sync_queue')) {
        final box = Hive.box<SyncQueueItem>('sync_queue');
        await box.clear();
        await box.close();
      }
    } catch (_) {}
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    if (Hive.isBoxOpen('sync_queue')) {
      await Hive.box<SyncQueueItem>('sync_queue').clear();
    }
  });

  Box<SyncQueueItem> queueBox() => Hive.box<SyncQueueItem>('sync_queue');

  SyncQueueItem? findItem(String collection, String documentId) {
    for (final item in queueBox().values) {
      if (item.collection == collection && item.id == documentId) return item;
    }
    return null;
  }

  group('Fleet queue counting + filtering', () {
    test('getQueuedFleetOperationCount counts only fleet_ collections', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {'asset_id': 'a1', 'description': 'grinding noise'},
        documentId: 'issue-count-1',
      );
      await SyncService().addToQueue(
        collection: 'fleet_photos',
        operation: 'upload',
        data: {'localPath': 'p.jpg', 'targetKind': 'issue', 'targetId': 'issue-count-1'},
        documentId: 'photo-count-1',
      );
      await SyncService().addToQueue(
        collection: 'waste_loads',
        operation: 'update',
        data: {'foo': 'bar'},
        documentId: 'not-fleet-1',
      );
      await SyncService().addToQueue(
        collection: 'job_cards',
        operation: 'create',
        data: {},
        documentId: 'not-fleet-2',
      );

      expect(SyncService().getQueuedFleetOperationCount(), 2,
          reason: 'only fleet_issues + fleet_photos counted; waste/job entries ignored');
    });
  });

  group('Fleet queue dedupe (startup + every process pass)', () {
    test('duplicate fleet entries with same collection/id/op collapse to newest', () async {
      // Two creates for the same issue id — e.g. the legacy double-queue bug
      // or a re-submit after a crash.
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {'description': 'older'},
        documentId: 'dup-issue-1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {'description': 'newer'},
        documentId: 'dup-issue-1',
      );
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {'description': 'distinct'},
        documentId: 'dup-issue-2',
      );

      expect(SyncService().getQueuedFleetOperationCount(), 3);

      // Dedupe runs at the top of every process pass, before Firestore is
      // touched (which throws in this no-Firebase harness).
      try {
        await SyncService().processNow();
      } catch (_) {}

      expect(SyncService().getQueuedFleetOperationCount(), 2,
          reason: 'older duplicate pruned, newest + distinct retained');
      final survivor = findItem(Collections.fleetIssues, 'dup-issue-1');
      expect(survivor, isNotNull);
      expect(survivor!.data['description'], 'newer');
    });

    test('deterministic photo queue ids make duplicate photo entries dedupable', () async {
      final id = FleetService.fleetPhotoQueueId(
        targetKind: 'issue',
        targetId: 'issue-photo-dup',
        localPath: '/tmp/photo_a.jpg',
      );
      // Same photo queued twice (pre-fix this produced two uploads → two URLs).
      await SyncService().addToQueue(
        collection: 'fleet_photos',
        operation: 'upload',
        data: {'localPath': '/tmp/photo_a.jpg', 'targetKind': 'issue', 'targetId': 'issue-photo-dup'},
        documentId: id,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await SyncService().addToQueue(
        collection: 'fleet_photos',
        operation: 'upload',
        data: {'localPath': '/tmp/photo_a.jpg', 'targetKind': 'issue', 'targetId': 'issue-photo-dup'},
        documentId: id,
      );
      // A different photo for the same issue keeps its own id.
      await SyncService().addToQueue(
        collection: 'fleet_photos',
        operation: 'upload',
        data: {'localPath': '/tmp/photo_b.jpg', 'targetKind': 'issue', 'targetId': 'issue-photo-dup'},
        documentId: FleetService.fleetPhotoQueueId(
          targetKind: 'issue',
          targetId: 'issue-photo-dup',
          localPath: '/tmp/photo_b.jpg',
        ),
      );

      try {
        await SyncService().processNow();
      } catch (_) {}

      expect(SyncService().getQueuedFleetOperationCount(), 2,
          reason: 'duplicate of photo_a pruned; photo_a + photo_b remain');
    });

    test('fleetPhotoQueueId is stable for same inputs and distinct across photos', () {
      final a1 = FleetService.fleetPhotoQueueId(
          targetKind: 'issue', targetId: 'x', localPath: '/tmp/a.jpg');
      final a2 = FleetService.fleetPhotoQueueId(
          targetKind: 'issue', targetId: 'x', localPath: '/tmp/a.jpg');
      final b = FleetService.fleetPhotoQueueId(
          targetKind: 'issue', targetId: 'x', localPath: '/tmp/b.jpg');
      final wr = FleetService.fleetPhotoQueueId(
          targetKind: 'work_record', targetId: 'x', localPath: '/tmp/a.jpg');
      expect(a1, a2);
      expect(a1, isNot(b));
      expect(a1, isNot(wr));
    });
  });

  group('Work record create_cf bookkeeping (duplicate-FM prevention)', () {
    Map<String, dynamic> createCfPayload() => {
          'asset_id': 'asset-1',
          'asset_name': 'Hyster 01',
          'title': 'Replaced hydraulic hose',
          'client_ref': 'wr-queue-1',
          '_pending_photo_paths': ['/tmp/wr_a.jpg', '/tmp/wr_b.jpg'],
          '_parts': [
            {'part_name': 'Hydraulic hose', 'quantity': 1},
          ],
          '_linked_issue_ids': ['issue-9'],
          '_resolver_clock_no': '77',
          '_resolver_name': 'Mechanic',
        };

    test('mutateQueuedItemData stamps _created_record_id and persists it', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetWorkRecords,
        operation: 'create_cf',
        data: SyncService.sanitizeForHive(createCfPayload()),
        documentId: 'wr-queue-1',
      );

      // Simulates the direct path right after the CF returns: the marker that
      // tells any replay "record exists — do not call the CF again".
      await SyncService().mutateQueuedItemData(
        collection: Collections.fleetWorkRecords,
        documentId: 'wr-queue-1',
        mutate: (d) => d['_created_record_id'] = 'record-abc',
      );

      final item = findItem(Collections.fleetWorkRecords, 'wr-queue-1');
      expect(item, isNotNull);
      expect(item!.data['_created_record_id'], 'record-abc',
          reason: 'replay must see the created record id and skip the CF call');
      expect(item.data['client_ref'], 'wr-queue-1',
          reason: 'client_ref doubles as the CF idempotency key for the lost-response case');
    });

    test('per-photo pruning removes only the uploaded path', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetWorkRecords,
        operation: 'create_cf',
        data: SyncService.sanitizeForHive(createCfPayload()),
        documentId: 'wr-queue-1',
      );

      await SyncService().mutateQueuedItemData(
        collection: Collections.fleetWorkRecords,
        documentId: 'wr-queue-1',
        mutate: (d) =>
            (d['_pending_photo_paths'] as List?)?.remove('/tmp/wr_a.jpg'),
      );

      final item = findItem(Collections.fleetWorkRecords, 'wr-queue-1');
      final remaining =
          (item!.data['_pending_photo_paths'] as List).cast<String>();
      expect(remaining, ['/tmp/wr_b.jpg'],
          reason: 'a replay must only re-attempt the photo that failed, never re-upload successes');
    });

    test('parts and linked-issue pruning leaves a minimal replay payload', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetWorkRecords,
        operation: 'create_cf',
        data: SyncService.sanitizeForHive(createCfPayload()),
        documentId: 'wr-queue-1',
      );

      await SyncService().mutateQueuedItemData(
        collection: Collections.fleetWorkRecords,
        documentId: 'wr-queue-1',
        mutate: (d) => d
          ..remove('_parts')
          ..remove('_linked_issue_ids')
          ..remove('_resolver_clock_no')
          ..remove('_resolver_name'),
      );

      final item = findItem(Collections.fleetWorkRecords, 'wr-queue-1');
      expect(item!.data.containsKey('_parts'), isFalse);
      expect(item.data.containsKey('_linked_issue_ids'), isFalse);
      expect(item.data['asset_id'], 'asset-1',
          reason: 'record payload itself is untouched by pruning');
    });

    test('removeQueuedItem clears the entry after a fully successful save', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetWorkRecords,
        operation: 'create_cf',
        data: SyncService.sanitizeForHive(createCfPayload()),
        documentId: 'wr-queue-1',
      );
      expect(SyncService().getQueuedFleetOperationCount(), 1);

      await SyncService().removeQueuedItem(
        collection: Collections.fleetWorkRecords,
        documentId: 'wr-queue-1',
      );

      expect(SyncService().getQueuedFleetOperationCount(), 0,
          reason: 'no entry left to replay → no duplicate work record possible');
    });

    test('mutateQueuedItemData safely no-ops on a missing item', () async {
      await SyncService().mutateQueuedItemData(
        collection: Collections.fleetWorkRecords,
        documentId: 'does-not-exist',
        mutate: (d) => d['_created_record_id'] = 'x',
      );
      expect(SyncService().getQueuedFleetOperationCount(), 0);
    });
  });

  group('Issue create replay safety', () {
    test('issue create entry can be removed after direct write (prevents replay overwrite)', () async {
      // Mirrors createIssueResilient: queue first…
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {
          'asset_id': 'a1',
          'description': 'loud grinding from mast',
          'status': 'open',
          'photos': <String>[],
          'created_at': DateTime.now().toIso8601String(),
        },
        documentId: 'issue-direct-1',
      );
      expect(SyncService().getQueuedFleetOperationCount(), 1);

      // …then remove the entry the moment the direct write lands. Before this
      // fix the entry stayed and its replay reset status to open / photos to []
      // — silently reverting an acknowledge/resolve made in the meantime.
      await SyncService().removeQueuedItem(
        collection: Collections.fleetIssues,
        documentId: 'issue-direct-1',
      );
      expect(SyncService().getQueuedFleetOperationCount(), 0);
    });

    test('fleet entries are retained when processing fails (no data loss on error)', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {'description': 'kept on failure'},
        documentId: 'issue-retain-1',
      );
      await SyncService().addToQueue(
        collection: 'fleet_photos',
        operation: 'upload',
        data: {'localPath': 'x.jpg', 'targetKind': 'issue', 'targetId': 'issue-retain-1'},
        documentId: 'photo-retain-1',
      );

      final before = SyncService().getQueuedFleetOperationCount();
      expect(before, 2);

      // No Firebase in harness → processing fails; entries must survive for retry.
      for (var i = 0; i < 3; i++) {
        try {
          await SyncService().processNow();
        } catch (_) {}
      }

      expect(SyncService().getQueuedFleetOperationCount(), before,
          reason: 'repeated failures never drop queued fleet work');
    });
  });

  group('getQueuedFleetDetails', () {
    test('empty queue yields empty details (robust empty state)', () {
      expect(SyncService().getQueuedFleetDetails(), isEmpty);
    });

    test('categorises issue / photo / work record entries with age', () async {
      await SyncService().addToQueue(
        collection: Collections.fleetIssues,
        operation: 'create',
        data: {'asset_name': 'Hyster 01', 'description': 'grinding'},
        documentId: 'det-issue',
      );
      await SyncService().addToQueue(
        collection: 'fleet_photos',
        operation: 'upload',
        data: {'localPath': 'p.jpg', 'targetKind': 'issue', 'targetId': 'det-issue'},
        documentId: 'det-photo',
      );
      await SyncService().addToQueue(
        collection: Collections.fleetWorkRecords,
        operation: 'create_cf',
        data: {'title': 'Replaced hose', 'asset_name': 'Hyster 01'},
        documentId: 'det-wr',
      );
      // Non-fleet must be excluded.
      await SyncService().addToQueue(
        collection: 'waste_loads',
        operation: 'update',
        data: {},
        documentId: 'det-non-fleet',
      );

      final details = SyncService().getQueuedFleetDetails();
      expect(details.length, 3);

      final types = details.map((d) => d['type'] as String).toSet();
      expect(types, contains('Problem report'));
      expect(types, contains('Photo upload'));
      expect(types, contains('Work record'));

      final wr = details.firstWhere((d) => d['id'] == 'det-wr');
      expect(wr['ref'], 'Replaced hose');
      expect(wr['age'], isNotNull);

      final photo = details.firstWhere((d) => d['id'] == 'det-photo');
      expect(photo['ref'], 'for a problem report');
    });
  });

  group('sanitizeForHive for fleet payloads', () {
    test('Timestamps and nested structures become Hive-safe', () {
      final ts = Timestamp.fromDate(DateTime(2026, 6, 10, 8, 30));
      final sanitized = SyncService.sanitizeForHive({
        'start_date': ts,
        '_parts': [
          {'part_name': 'Mast chain', 'quantity': 2},
        ],
        '_pending_photo_paths': ['/tmp/a.jpg'],
        'nested': {'end_date': ts},
      });

      expect(sanitized['start_date'], isA<String>());
      expect(DateTime.parse(sanitized['start_date'] as String),
          DateTime(2026, 6, 10, 8, 30));
      expect((sanitized['nested'] as Map)['end_date'], isA<String>());
      expect(sanitized['_parts'], isA<List>());
      expect(((sanitized['_parts'] as List).first as Map)['quantity'], 2);
      expect(sanitized['_pending_photo_paths'], ['/tmp/a.jpg']);
    });
  });
}
