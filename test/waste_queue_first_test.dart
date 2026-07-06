import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

bool isRemotePhotoUrl(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

({List<String> remote, List<String> local}) splitPhotoPaths(
  List<String> paths,
) {
  final remote = <String>[];
  final local = <String>[];
  for (final path in paths) {
    if (isRemotePhotoUrl(path)) {
      remote.add(path);
    } else {
      local.add(path);
    }
  }
  return (remote: remote, local: local);
}

/// Mirrors WasteService stable id helpers (private in production).
String stableWasteItemDocId(String loadId, String submitRef, int index) {
  const namespace = 'a3f2c8e1-4b5d-6e7f-8901-23456789abcd';
  return const Uuid().v5(namespace, 'waste_item:$loadId:$submitRef:$index');
}

void main() {
  group('Queue-first waste submit ids', () {
    test('stable item doc ids are deterministic per load + submit ref + index', () {
      const loadId = 'load-abc';
      const submitRef = '11111111-2222-3333-4444-555555555555';
      final a = stableWasteItemDocId(loadId, submitRef, 0);
      final b = stableWasteItemDocId(loadId, submitRef, 0);
      final c = stableWasteItemDocId(loadId, submitRef, 1);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('different submit refs produce different item doc ids', () {
      const loadId = 'load-abc';
      final ref1 = stableWasteItemDocId(loadId, 'ref-one', 0);
      final ref2 = stableWasteItemDocId(loadId, 'ref-two', 0);
      expect(ref1, isNot(ref2));
    });
  });

  group('Photo path split (stock URL pass-through)', () {
    test('remote URLs stay in item photos; locals queue separately', () {
      const remote = 'https://firebasestorage.googleapis.com/v0/b/x/o/y.jpg';
      const local = '/data/waste_media_queue/capture_1.jpg';
      final split = splitPhotoPaths([remote, local, remote]);
      expect(split.remote, [remote, remote]);
      expect(split.local, [local]);
    });

    test('all-local paths queue; no remote pass-through', () {
      final split = splitPhotoPaths(['/a.jpg', '/b.jpg']);
      expect(split.remote, isEmpty);
      expect(split.local, ['/a.jpg', '/b.jpg']);
    });
  });
}