import '../services/sync_service.dart';

/// Ordered Hive queue plan for guard-facing waste saves.
/// Persists all media in parallel, then writes queue entries in one pass.
final class WasteQueueBatchPlan {
  final List<_WasteQueueStep> _steps = [];

  bool get isEmpty => _steps.isEmpty;
  int get length => _steps.length;

  void addFirestore({
    required String collection,
    required String operation,
    required Map<String, dynamic> data,
    required String documentId,
  }) {
    _steps.add(_FirestoreStep(
      collection: collection,
      operation: operation,
      data: data,
      documentId: documentId,
    ));
  }

  void addPhoto({
    required String localPath,
    required String loadId,
    required String queueDocumentId,
    String? itemId,
    String? targetCollection,
  }) {
    _steps.add(_PhotoStep(
      localPath: localPath,
      loadId: loadId,
      queueDocumentId: queueDocumentId,
      itemId: itemId,
      targetCollection: targetCollection,
    ));
  }

  void addSignature({
    required String localPath,
    required String loadId,
    required String queueDocumentId,
  }) {
    _steps.add(_SignatureStep(
      localPath: localPath,
      loadId: loadId,
      queueDocumentId: queueDocumentId,
    ));
  }

  Future<void> flush() async {
    if (_steps.isEmpty) return;

    final mediaPaths = <String>[];
    for (final step in _steps) {
      if (step is _PhotoStep) {
        mediaPaths.add(step.localPath);
      } else if (step is _SignatureStep) {
        mediaPaths.add(step.localPath);
      }
    }

    final persisted = mediaPaths.isEmpty
        ? const <String>[]
        : await SyncService.persistWasteMediaBatch(mediaPaths);

    var mediaIndex = 0;
    final entries = <SyncQueueBatchEntry>[];

    for (final step in _steps) {
      switch (step) {
        case _FirestoreStep s:
          entries.add(SyncQueueBatchEntry(
            collection: s.collection,
            operation: s.operation,
            data: s.data,
            documentId: s.documentId,
          ));
        case _PhotoStep s:
          final path = persisted[mediaIndex++];
          entries.add(SyncQueueBatchEntry(
            collection: 'waste_photos',
            operation: 'upload',
            data: {
              'localPath': path,
              'loadId': s.loadId,
              if (s.itemId != null) 'itemId': s.itemId,
              if (s.targetCollection != null)
                'targetCollection': s.targetCollection,
            },
            documentId: s.queueDocumentId,
          ));
        case _SignatureStep s:
          final path = persisted[mediaIndex++];
          entries.add(SyncQueueBatchEntry(
            collection: 'waste_signatures',
            operation: 'upload',
            data: {
              'localPath': path,
              'loadId': s.loadId,
            },
            documentId: s.queueDocumentId,
          ));
      }
    }

    await SyncService().addAllToQueue(entries);
  }
}

sealed class _WasteQueueStep {}

final class _FirestoreStep extends _WasteQueueStep {
  final String collection;
  final String operation;
  final Map<String, dynamic> data;
  final String documentId;

  _FirestoreStep({
    required this.collection,
    required this.operation,
    required this.data,
    required this.documentId,
  });
}

final class _PhotoStep extends _WasteQueueStep {
  final String localPath;
  final String loadId;
  final String queueDocumentId;
  final String? itemId;
  final String? targetCollection;

  _PhotoStep({
    required this.localPath,
    required this.loadId,
    required this.queueDocumentId,
    this.itemId,
    this.targetCollection,
  });
}

final class _SignatureStep extends _WasteQueueStep {
  final String localPath;
  final String loadId;
  final String queueDocumentId;

  _SignatureStep({
    required this.localPath,
    required this.loadId,
    required this.queueDocumentId,
  });
}