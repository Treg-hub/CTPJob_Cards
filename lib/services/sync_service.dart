import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../constants/collections.dart';
import '../models/sync_queue_item.dart';
import 'connectivity_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  late final Box<SyncQueueItem> _queueBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Future<void> init() async {
    _queueBox = Hive.box<SyncQueueItem>('sync_queue');
    _startListening();
    // Drain any items left from the previous session. Without this, queued
    // uploads only process on the next connectivity *change*, so items queued
    // while already online would sit indefinitely.
    if (_queueBox.isNotEmpty) {
      _processQueue();
    }
  }

  void _startListening() {
    _connectivitySubscription = ConnectivityService().connectivityStream.listen((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      if (isOnline) {
        _processQueue();
      }
    });
  }

  Future<void> addToQueue({
    required String collection,
    required String operation,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    final id = documentId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final item = SyncQueueItem(
      id: id,
      collection: collection,
      operation: operation,
      data: _sanitizeForHive(data),
      createdAt: DateTime.now(),
    );

    await _queueBox.add(item);
    debugPrint('✅ Added to sync queue: $operation $collection');
  }

  /// Strips Firestore sentinel types that Hive cannot serialize.
  /// - FieldValue (serverTimestamp, arrayUnion, increment, delete) → ISO-8601 string of now.
  /// - Timestamp → ISO-8601 string of the equivalent DateTime.
  /// Nested maps are recursed; lists are walked for the same types.
  static Map<String, dynamic> _sanitizeForHive(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      result[entry.key] = _sanitizeValue(entry.value);
    }
    return result;
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value is FieldValue) {
      return DateTime.now().toIso8601String();
    }
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is Map<String, dynamic>) {
      return _sanitizeForHive(value);
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList();
    }
    return value;
  }

  Future<void> _processQueue() async {
    if (_queueBox.isEmpty) return;

    final items = _queueBox.values.toList();
    final firestore = FirebaseFirestore.instance;

    for (var item in items) {
      try {
        if (item.collection == 'copper_inventory') {
          final docRef = firestore.doc('copper_inventory/main');
          await docRef.set(item.data, SetOptions(merge: true));
        } else if (item.collection.startsWith('waste_')) {
          // WasteTrack operations - handle photos and documents
          if (item.collection == 'waste_photos' && item.operation == 'upload') {
            await _processWastePhotoUpload(item);
          } else if (item.collection == 'waste_signatures' && item.operation == 'upload') {
            await _processWasteSignatureUpload(item);
          } else {
            final docRef = firestore.collection(item.collection).doc(item.id);
            if (item.operation == 'create' || item.operation == 'update') {
              await docRef.set(item.data, SetOptions(merge: true));
            } else if (item.operation == 'delete') {
              await docRef.delete();
            }
          }
        } else {
          final docRef = firestore.collection(item.collection).doc(item.id);

          if (item.operation == 'create' || item.operation == 'update') {
            await docRef.set(item.data, SetOptions(merge: true));
          } else if (item.operation == 'delete') {
            await docRef.delete();
          }
        }

        await item.delete();
        debugPrint('✅ Synced from queue: ${item.operation} ${item.collection}');
      } catch (e) {
        debugPrint('❌ Failed to sync item: $e');
      }
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Returns approximate count of queued waste-related operations for UI indicators.
  /// Robust: safe if box not yet open (returns 0). Uses startsWith('waste_') which covers
  /// waste_loads, waste_items, waste_audit, waste_* + the synthetic 'waste_photos'/'waste_signatures' queue keys.
  int getQueuedWasteOperationCount() {
    try {
      if (!_queueBox.isOpen) return 0;
      return _queueBox.values
          .where((item) => item.collection.startsWith('waste_'))
          .length;
    } catch (_) {
      return 0; // robustness for any edge timing / hot-reload
    }
  }

  /// Lightweight per-item breakdown of queued waste operations by type.
  /// Used by WasteHomeScreen for tap-to-reveal visibility of what is queued (photos, signatures, etc.).
  /// Returns map of friendly type label (singular base) -> count. Safe/robust like getQueuedWasteOperationCount.
  /// Does not change any queuing logic.
  Map<String, int> getQueuedWasteBreakdown() {
    try {
      if (!_queueBox.isOpen) return {};
      final Map<String, int> counts = {};
      for (final item in _queueBox.values) {
        if (!item.collection.startsWith('waste_')) continue;
        String type;
        switch (item.collection) {
          case 'waste_photos':
            type = 'photo';
            break;
          case 'waste_signatures':
            type = 'signature';
            break;
          case 'waste_loads':
            type = 'load/weighbridge update';
            break;
          case 'waste_items':
            type = 'item';
            break;
          case 'waste_audit':
            type = 'audit';
            break;
          default:
            // e.g. other waste_* collections
            final suffix = item.collection.substring('waste_'.length);
            type = 'other ($suffix)';
            break;
        }
        counts[type] = (counts[type] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      return {};
    }
  }

  /// Detailed list of queued waste operations for the new lightweight Queued Operations view / screen.
  /// Provides per-item basics: type, load reference (if present in queue data), relative age.
  /// Safe/robust (matches sibling helpers). Sorted newest-first. Small surface, no logic change.
  /// Used by waste_queued_screen.dart and (optionally) home card.
  List<Map<String, dynamic>> getQueuedWasteDetails() {
    try {
      if (!_queueBox.isOpen) return [];
      final now = DateTime.now();
      final List<Map<String, dynamic>> details = [];
      for (final item in _queueBox.values) {
        if (!item.collection.startsWith('waste_')) continue;
        String type;
        String? loadRef;
        switch (item.collection) {
          case 'waste_photos':
            type = 'Photo upload';
            loadRef = item.data['loadId'] as String?;
            final itemId = item.data['itemId'] as String?;
            if (itemId != null) {
              loadRef = loadRef != null ? '$loadRef (item $itemId)' : 'item $itemId';
            }
            break;
          case 'waste_signatures':
            type = 'Signature upload';
            loadRef = item.data['loadId'] as String?;
            break;
          case 'waste_loads':
            type = (item.operation == 'create') ? 'Load create' : 'Load/weighbridge update';
            loadRef = (item.data['load_number'] as String?) ??
                      (item.data['loadId'] as String?) ??
                      item.id;
            break;
          case 'waste_items':
            type = 'Waste item create';
            loadRef = (item.data['loadId'] as String?) ?? (item.data['load_number'] as String?);
            break;
          default:
            final suffix = item.collection.substring('waste_'.length);
            type = 'Other ($suffix)';
            loadRef = (item.data['loadId'] as String?) ?? (item.data['load_number'] as String?);
        }
        final age = _formatRelativeAge(now, item.createdAt);
        details.add({
          'id': item.id,
          'type': type,
          'loadRef': loadRef,
          'age': age,
          'createdAt': item.createdAt,
          'collection': item.collection,
          'operation': item.operation,
        });
      }
      details.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));
      return details;
    } catch (_) {
      return [];
    }
  }

  String _formatRelativeAge(DateTime now, DateTime createdAt) {
    final diff = now.difference(createdAt);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Public trigger for manual retry from UI (Waste home, etc.).
  /// Forces an immediate pass over the Hive queue (including any waste photos/docs).
  Future<void> processNow() async {
    await _processQueue();
  }

  /// Handles a queued waste photo upload from the central Hive queue.
  /// Uploads the local file to Storage, then patches the target waste_load or waste_item
  /// with the resulting URL using arrayUnion (safe for concurrent retries).
  /// Only the caller (inside try of _processQueue) will delete the queue item on success.
  Future<void> _processWastePhotoUpload(SyncQueueItem item) async {
    final data = item.data;
    final String? localPath = data['localPath'] as String?;
    final String? loadId = data['loadId'] as String?;
    final String? itemId = data['itemId'] as String?;

    if (localPath == null || loadId == null) {
      debugPrint('⚠️ Invalid waste_photos queue entry, skipping: ${item.id}');
      return; // will not delete; manual cleanup later if needed
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('⚠️ Local photo no longer exists for queue item ${item.id}: $localPath');
      // Allow delete so we don't retry forever on deleted temp files
      return;
    }

    // Upload to Storage (mirrors WasteService.uploadWastePhoto path convention)
    final fileName = '${const Uuid().v4()}.jpg';
    final storageFolder = itemId != null ? 'waste_items/$itemId' : 'waste_loads/$loadId';
    final storagePath = '$storageFolder/photos/$fileName';

    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final snapshot = await ref.putFile(file);
    final downloadUrl = await snapshot.ref.getDownloadURL();

    // Patch the target document (load or item) - arrayUnion is idempotent-friendly
    final targetCollection = itemId != null ? Collections.wasteItems : Collections.wasteLoads;
    final targetDocId = itemId ?? loadId;
    final photoField = itemId != null ? 'photos' : 'load_photos';

    await FirebaseFirestore.instance
        .collection(targetCollection)
        .doc(targetDocId)
        .update({
      photoField: FieldValue.arrayUnion([downloadUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('✅ Waste photo synced from queue → $targetCollection/$targetDocId');
    // Success: _processQueue will delete the item after this returns without throw
  }

  /// Handles a queued waste signature (bytes) upload from the central Hive queue.
  /// Reads temp file, uploads PNG bytes to Storage under `waste_loads/{loadId}/signature/...` (reuses existing path convention),
  /// patches driver_signature_url on the waste load doc (equivalent part of markLoadComplete; status/completed fields are queued separately by UI),
  /// then cleans up the temp file. Mirrors _processWastePhotoUpload exactly in structure/resilience.
  Future<void> _processWasteSignatureUpload(SyncQueueItem item) async {
    final data = item.data;
    final String? localPath = data['localPath'] as String?;
    final String? loadId = data['loadId'] as String?;

    if (localPath == null || loadId == null) {
      debugPrint('⚠️ Invalid waste_signatures queue entry, skipping: ${item.id}');
      return; // will not delete; manual cleanup later if needed
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('⚠️ Local signature file no longer exists for queue item ${item.id}: $localPath');
      // Allow delete so we don't retry forever on deleted temp files
      return;
    }

    final bytes = await file.readAsBytes();

    // Upload to Storage under correct signature path (matches WasteService._uploadSignatureBytesDirect convention)
    final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
    final storagePath = 'waste_loads/$loadId/signature/$fileName';

    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final snapshot = await ref.putData(bytes);
    final downloadUrl = await snapshot.ref.getDownloadURL();

    // Patch only the signature URL (status/complete/actor fields handled by parallel wasteLoads update queue or direct call)
    await FirebaseFirestore.instance
        .collection(Collections.wasteLoads)
        .doc(loadId)
        .update({
      'driver_signature_url': downloadUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Cleanup temp file on success (matches legacy session signature processor in WasteService)
    try {
      await file.delete();
    } catch (_) {}

    debugPrint('✅ Waste signature synced from queue → waste_loads/$loadId');
    // Success: _processQueue will delete the queue item after this returns without throw
  }

  /// Removes ONE specific queued waste item (by matching details from getQueuedWasteDetails).
  /// Safe delete from Hive box only — does not affect server data or session queues.
  /// Used for per-item "Remove from queue" action in WasteQueuedScreen.
  Future<void> removeSpecificQueuedWasteItem(Map<String, dynamic> detail) async {
    try {
      if (!_queueBox.isOpen) return;
      final targetId = detail['id'] as String?;
      final targetCollection = detail['collection'] as String?;
      final targetOp = detail['operation'] as String?;
      final targetCreated = detail['createdAt'] as DateTime?;

      final items = _queueBox.values.toList(); // snapshot for safe iteration
      for (final item in items) {
        if (item.collection == targetCollection &&
            item.id == targetId &&
            item.operation == targetOp &&
            (targetCreated == null || item.createdAt == targetCreated)) {
          await item.delete();
          debugPrint('🗑️ Removed specific queued waste item via UI: $targetCollection/$targetId');
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ removeSpecificQueuedWasteItem error (safe no-op): $e');
    }
  }

  /// Targeted retry for a SINGLE queued waste item (from WasteQueuedScreen per-item action).
  /// Attempts the same processing logic as the central queue for this item only.
  /// On success: deletes the queue entry. On failure: leaves it in queue for later.
  /// Returns true only if this specific item was processed and removed.
  Future<bool> retrySpecificQueuedWasteItem(Map<String, dynamic> detail) async {
    try {
      if (!_queueBox.isOpen) return false;
      final targetId = detail['id'] as String?;
      final targetCollection = detail['collection'] as String?;
      final targetOp = detail['operation'] as String?;
      final targetCreated = detail['createdAt'] as DateTime?;

      final items = _queueBox.values.toList();
      for (final item in items) {
        if (item.collection == targetCollection &&
            item.id == targetId &&
            item.operation == targetOp &&
            (targetCreated == null || item.createdAt == targetCreated)) {
          bool succeeded = false;
          try {
            if (item.collection == 'copper_inventory') {
              final docRef = FirebaseFirestore.instance.doc('copper_inventory/main');
              await docRef.set(item.data, SetOptions(merge: true));
              succeeded = true;
            } else if (item.collection.startsWith('waste_')) {
              if (item.collection == 'waste_photos' && item.operation == 'upload') {
                await _processWastePhotoUpload(item);
                succeeded = true;
              } else if (item.collection == 'waste_signatures' && item.operation == 'upload') {
                await _processWasteSignatureUpload(item);
                succeeded = true;
              } else {
                final docRef = FirebaseFirestore.instance.collection(item.collection).doc(item.id);
                if (item.operation == 'create' || item.operation == 'update') {
                  await docRef.set(item.data, SetOptions(merge: true));
                } else if (item.operation == 'delete') {
                  await docRef.delete();
                }
                succeeded = true;
              }
            } else {
              final docRef = FirebaseFirestore.instance.collection(item.collection).doc(item.id);
              if (item.operation == 'create' || item.operation == 'update') {
                await docRef.set(item.data, SetOptions(merge: true));
              } else if (item.operation == 'delete') {
                await docRef.delete();
              }
              succeeded = true;
            }
          } catch (e) {
            debugPrint('❌ Targeted per-item retry failed for ${item.collection}/${item.id}: $e');
            succeeded = false;
          }

          if (succeeded) {
            await item.delete();
            debugPrint('✅ Targeted retry succeeded + removed: ${item.collection}/${item.id}');
            return true;
          }
          // Leave in queue on failure (safe for future full retry)
          return false;
        }
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ retrySpecificQueuedWasteItem error: $e');
      return false;
    }
  }
}