import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ctp_job_cards/models/sync_queue_item.dart';
import 'package:ctp_job_cards/services/sync_service.dart';
import 'package:ctp_job_cards/utils/waste_queue_batch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp
        .createTemp('waste_queue_batch_test_');
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

  tearDown(() async {
    if (Hive.isBoxOpen('sync_queue')) {
      await Hive.box<SyncQueueItem>('sync_queue').clear();
    }
  });

  tearDownAll(() async {
    try {
      if (Hive.isBoxOpen('sync_queue')) {
        await Hive.box<SyncQueueItem>('sync_queue').close();
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('WasteQueueBatchPlan', () {
    test('flush preserves op order: load, photos, item, signature', () async {
      final srcA = File('${tempDir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      final srcB = File('${tempDir.path}/b.jpg')..writeAsBytesSync([4, 5, 6]);
      final sig = File('${tempDir.path}/sig.png')..writeAsBytesSync([7, 8]);

      final plan = WasteQueueBatchPlan();
      plan.addFirestore(
        collection: 'waste_loads',
        operation: 'update',
        data: {'status': 'pending_weighbridge'},
        documentId: 'load-1',
      );
      plan.addPhoto(
        localPath: srcA.path,
        loadId: 'load-1',
        queueDocumentId: 'load-1_photo_0',
      );
      plan.addPhoto(
        localPath: srcB.path,
        loadId: 'load-1',
        queueDocumentId: 'load-1_photo_1',
        itemId: 'item-0',
      );
      plan.addFirestore(
        collection: 'waste_items',
        operation: 'set',
        data: {'subtype': 'Paper'},
        documentId: 'item-0',
      );
      plan.addSignature(
        localPath: sig.path,
        loadId: 'load-1',
        queueDocumentId: 'load-1_sig',
      );

      await plan.flush();

      final box = Hive.box<SyncQueueItem>('sync_queue');
      expect(box.length, 5);
      final ops = box.values.map((i) => '${i.operation}:${i.collection}').toList();
      expect(ops[0], 'update:waste_loads');
      expect(ops[1], 'upload:waste_photos');
      expect(ops[2], 'upload:waste_photos');
      expect(ops[3], 'set:waste_items');
      expect(ops[4], 'upload:waste_signatures');
    });
  });

  group('SyncService.persistWasteMediaBatch', () {
    test('returns paths in input order', () async {
      final files = <File>[];
      for (var i = 0; i < 5; i++) {
        final f = File('${tempDir.path}/batch_$i.jpg')
          ..writeAsBytesSync([i]);
        files.add(f);
      }
      final out = await SyncService.persistWasteMediaBatch(
        files.map((f) => f.path).toList(),
        concurrency: 3,
      );
      expect(out.length, 5);
      for (var i = 0; i < out.length; i++) {
        expect(File(out[i]).existsSync(), isTrue);
        if (out[i].contains(SyncService.wasteMediaQueueDirName)) {
          expect(out[i], isNot(files[i].path));
        } else {
          expect(out[i], files[i].path);
        }
      }
    });
  });
}