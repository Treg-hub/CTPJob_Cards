import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show ValueListenable, debugPrint;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../constants/collections.dart';
import '../models/sync_queue_item.dart';
import '../utils/waste_collection_marker.dart';
import 'connectivity_service.dart';

/// One Hive queue row for [SyncService.addAllToQueue].
class SyncQueueBatchEntry {
  final String collection;
  final String operation;
  final Map<String, dynamic> data;
  final String documentId;

  const SyncQueueBatchEntry({
    required this.collection,
    required this.operation,
    required this.data,
    required this.documentId,
  });
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  // Matches new-format W-NNNN numbers; legacy WT-YYYYMMDD-NNN treated as valid too.
  static final RegExp _properLoadNumber = RegExp(r'^W-\d{4,}$');
  static final RegExp _legacyLoadNumber  = RegExp(r'^WT-\d{8}-\d{3}$');
  static final RegExp _properSecurityEntryNumber = RegExp(r'^SEC-\d{4,}$');
  // Lazy: resolving the Firebase app at singleton construction breaks any
  // context without an initialized app (the offline-resilience test harness).
  late final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'africa-south1');

  /// Public Hive-safe sanitizer for offline queue payloads.
  static Map<String, dynamic> sanitizeForHive(Map<String, dynamic> data) =>
      _sanitizeForHive(data);

  /// Subdirectory of the app documents dir holding queued offline media
  /// (photos/signatures). Files here are owned by the sync queue and deleted
  /// after a successful upload.
  static const String wasteMediaQueueDirName = 'waste_media_queue';
  static String? _cachedWasteMediaQueueDir;

  /// Resolved path to the durable waste media queue directory (cached).
  static Future<String> wasteMediaQueueDirectory() async {
    final cached = _cachedWasteMediaQueueDir;
    if (cached != null && Directory(cached).existsSync()) return cached;
    _cachedWasteMediaQueueDir = null;
    final docsDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}$wasteMediaQueueDirName',
    );
    if (!queueDir.existsSync()) {
      queueDir.createSync(recursive: true);
    }
    _cachedWasteMediaQueueDir = queueDir.path;
    return queueDir.path;
  }

  /// Copies a queued media file into the persistent app documents dir so it
  /// survives OS cache clears while waiting for sync. Copy, not move —
  /// screens may still display the cache original. The destination name is a
  /// deterministic transform of the source path, so re-queueing the same
  /// capture (a user retrying a submit offline) maps to the same file and the
  /// localPath-based queue dedupe collapses the duplicates. Falls back to the
  /// original path on any error (queueing must never be blocked by a copy
  /// failure). Lives here (not WasteService) so queue migration can run
  /// without touching Firebase-backed services.
  static Future<String> persistWasteMediaForQueue(String localPath) async {
    try {
      if (localPath.contains(wasteMediaQueueDirName)) return localPath;
      final source = File(localPath);
      if (!source.existsSync()) return localPath;
      final queueDirPath = await wasteMediaQueueDirectory();
      final destName = localPath.replaceAll(RegExp(r'[\\/:]'), '_');
      final destPath =
          '$queueDirPath${Platform.pathSeparator}$destName';
      if (File(destPath).existsSync()) return destPath;
      await source.copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('⚠️ persistWasteMediaForQueue failed, queueing original path: $e');
      return localPath;
    }
  }

  /// Parallel media copies for large guard saves (bounded concurrency).
  static Future<List<String>> persistWasteMediaBatch(
    List<String> localPaths, {
    int concurrency = 8,
  }) async {
    if (localPaths.isEmpty) return const [];
    if (concurrency < 1) concurrency = 1;
    final out = List<String>.filled(localPaths.length, '');
    for (var start = 0; start < localPaths.length; start += concurrency) {
      final end = start + concurrency > localPaths.length
          ? localPaths.length
          : start + concurrency;
      await Future.wait([
        for (var i = start; i < end; i++)
          persistWasteMediaForQueue(localPaths[i]).then((p) => out[i] = p),
      ]);
    }
    return out;
  }

  late final Box<SyncQueueItem> _queueBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Reentrancy guard: connectivity flaps (load shedding, factory Wi-Fi) fire
  // the listener repeatedly; without this two passes can process the same
  // queue item concurrently.
  bool _isProcessing = false;

  /// Last sync error per queued fleet/waste item (`collection:id` → message).
  /// In-memory only — cleared on success or when the item leaves the queue.
  final Map<String, String> _queueLastErrors = {};

  String _queueErrorKey(String collection, String documentId) =>
      '$collection:$documentId';

  void _setQueueLastError(SyncQueueItem item, Object error) {
    if (!item.collection.startsWith('fleet_') &&
        !item.collection.startsWith('waste_')) {
      return;
    }
    _queueLastErrors[_queueErrorKey(item.collection, item.id)] =
        error.toString();
  }

  void _clearQueueLastError(SyncQueueItem item) {
    _queueLastErrors.remove(_queueErrorKey(item.collection, item.id));
  }

  Future<void> init() async {
    _queueBox = Hive.box<SyncQueueItem>('sync_queue');
    _startListening();
    // Drain any items left from the previous session. Without this, queued
    // uploads only process on the next connectivity *change*, so items queued
    // while already online would sit indefinitely.
    if (_queueBox.isNotEmpty) {
      await migrateQueuedWasteMediaToPersistentDir();
      _dedupeWasteQueue();
      _processQueue();
    }
  }

  /// Live Hive listenable for queue UI (WasteQueuedScreen, home banners).
  /// Safe only after [init] — callers should catch if box is not open yet.
  ValueListenable<Box<SyncQueueItem>> get queueListenable =>
      _queueBox.listenable();

  /// One-time healing for queue entries created before media files were
  /// persisted to the app documents dir: any photo/signature entry whose
  /// localPath still points at a volatile location (cache/temp) is copied
  /// into waste_media_queue/ and the entry rewritten. Entries whose file is
  /// already gone are left untouched — replay surfaces them as media_lost.
  Future<void> migrateQueuedWasteMediaToPersistentDir() async {
    try {
      if (!_queueBox.isOpen) return;
      for (final item in _queueBox.values.toList()) {
        if (item.collection != 'waste_photos' &&
            item.collection != 'waste_signatures') {
          continue;
        }
        final localPath = item.data['localPath'] as String?;
        if (localPath == null ||
            localPath.contains(wasteMediaQueueDirName)) {
          continue;
        }
        if (!File(localPath).existsSync()) continue;
        final persistentPath = await persistWasteMediaForQueue(localPath);
        if (persistentPath != localPath) {
          item.data['localPath'] = persistentPath;
          await item.save();
        }
      }
    } catch (e) {
      debugPrint('⚠️ migrateQueuedWasteMediaToPersistentDir error (safe no-op): $e');
    }
  }

  /// Drops older duplicate Firestore queue entries (same collection/doc/op).
  /// Photo/signature uploads are deduped by localPath instead — one capture
  /// produces one unique file path, so two entries with the same path are the
  /// same upload queued twice (e.g. a user retrying a submit while offline).
  void _dedupeWasteQueue() {
    try {
      if (!_queueBox.isOpen) return;

      // Merge multiple waste_loads updates for the same doc (status + photo_count
      // etc.) instead of dropping the older payload.
      final mergedLoadUpdates = <String, SyncQueueItem>{};
      final mergedAway = <SyncQueueItem>[];
      for (final item in _queueBox.values.toList()) {
        if (item.collection != Collections.wasteLoads ||
            item.operation != 'update') {
          continue;
        }
        final existing = mergedLoadUpdates[item.id];
        if (existing == null) {
          mergedLoadUpdates[item.id] = item;
        } else {
          final mergedData = Map<String, dynamic>.from(existing.data);
          mergedData.addAll(item.data);
          existing.data
            ..clear()
            ..addAll(mergedData);
          mergedAway.add(item);
        }
      }
      for (final item in mergedAway) {
        item.delete();
        debugPrint(
          '🗑️ Merged waste_loads update into surviving entry for ${item.id}',
        );
      }

      final seen = <String, SyncQueueItem>{};
      final toDelete = <SyncQueueItem>[];
      for (final item in _queueBox.values.toList()) {
        if (!item.collection.startsWith('waste_')) continue;
        final String key;
        if (item.collection == 'waste_photos' ||
            item.collection == 'waste_signatures') {
          final localPath = item.data['localPath'] as String?;
          if (localPath == null) continue;
          key = '${item.collection}:$localPath';
        } else {
          key = '${item.collection}:${item.id}:${item.operation}';
        }
        final existing = seen[key];
        if (existing == null) {
          seen[key] = item;
        } else if (item.createdAt.isAfter(existing.createdAt)) {
          toDelete.add(existing);
          seen[key] = item;
        } else {
          toDelete.add(item);
        }
      }
      for (final item in toDelete) {
        item.delete();
        debugPrint('🗑️ Pruned duplicate queue entry: ${item.collection}/${item.id}');
      }
    } catch (e) {
      debugPrint('⚠️ _dedupeWasteQueue error (safe no-op): $e');
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
    await addAllToQueue([
      SyncQueueBatchEntry(
        collection: collection,
        operation: operation,
        data: data,
        documentId:
            documentId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    ]);
  }

  /// Writes multiple queue entries in order with a single flush pass.
  Future<void> addAllToQueue(List<SyncQueueBatchEntry> entries) async {
    if (entries.isEmpty) return;
    for (final entry in entries) {
      final item = SyncQueueItem(
        id: entry.documentId,
        collection: entry.collection,
        operation: entry.operation,
        data: _sanitizeForHive(entry.data),
        createdAt: DateTime.now(),
      );
      await _queueBox.add(item);
    }
    if (entries.length == 1) {
      final e = entries.first;
      debugPrint('✅ Added to sync queue: ${e.operation} ${e.collection}');
    } else {
      debugPrint('✅ Added ${entries.length} entries to sync queue (batch)');
    }
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

  /// Drops older duplicate fleet queue entries (same collection/doc/op).
  /// Photo entries use deterministic ids (issue_{id}_{pathHash}), so two
  /// entries with the same key are true duplicates of the same upload.
  /// create_cf entries have unique queue ids and are never deduped.
  void _dedupeFleetQueue() {
    try {
      if (!_queueBox.isOpen) return;
      final seen = <String, SyncQueueItem>{};
      final toDelete = <SyncQueueItem>[];
      for (final item in _queueBox.values.toList()) {
        if (!item.collection.startsWith('fleet_')) continue;
        final key = '${item.collection}:${item.id}:${item.operation}';
        final existing = seen[key];
        if (existing == null) {
          seen[key] = item;
        } else if (item.createdAt.isAfter(existing.createdAt)) {
          toDelete.add(existing);
          seen[key] = item;
        } else {
          toDelete.add(item);
        }
      }
      for (final item in toDelete) {
        item.delete();
        debugPrint('🗑️ Pruned duplicate fleet queue entry: ${item.collection}/${item.id}');
      }
    } catch (e) {
      debugPrint('⚠️ _dedupeFleetQueue error (safe no-op): $e');
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (_queueBox.isEmpty) return;
    _dedupeWasteQueue();
    _dedupeFleetQueue();
    _isProcessing = true;
    try {
      await _processQueueInner();
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processQueueInner() async {
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
            final payload = _restoreWastePayload(item.collection, item.data);
            if (item.operation == 'create' ||
                item.operation == 'update' ||
                item.operation == 'set') {
              final merge = item.operation == 'update' ||
                  item.operation == 'set' ||
                  (item.collection == Collections.wasteLoads &&
                      (item.operation == 'create' || item.operation == 'set'));
              await docRef.set(
                payload,
                SetOptions(merge: merge),
              );
              if (item.collection == Collections.wasteLoads &&
                  (item.operation == 'set' || item.operation == 'create')) {
                await _assignWasteLoadNumberIfNeeded(item.id, item.data);
              }
              if (item.collection == Collections.wasteLoads) {
                if (item.data.containsKey('photo_count') ||
                    item.data.containsKey('load_photos') ||
                    _loadStatusPastCollection(item.data['status'] as String?)) {
                  await _recomputeWastePhotoCount(item.id);
                }
                await _maybeClearCollectionMarkerAfterLoadSync(
                  item.id,
                  item.data,
                );
              }
            } else if (item.operation == 'delete') {
              await docRef.delete();
            }
          }
        } else if (item.collection.startsWith('fleet_')) {
          await _processFleetQueueItem(item, firestore);
        } else if (item.collection.startsWith('security_')) {
          await _processSecurityQueueItem(item, firestore);
        } else if (item.collection.startsWith('work_report_')) {
          final docRef = firestore.collection(item.collection).doc(item.id);
          final payload = _restoreWorkReportTimestamps(item.data);
          if (item.operation == 'create' ||
              item.operation == 'update' ||
              item.operation == 'set') {
            await docRef.set(
              payload,
              SetOptions(merge: item.operation != 'create'),
            );
          } else if (item.operation == 'delete') {
            await docRef.delete();
          }
        } else {
          final docRef = firestore.collection(item.collection).doc(item.id);
          // Job cards: queue sanitisation turned every Timestamp into an
          // ISO-8601 string. Replaying those verbatim corrupted the doc and
          // crashed JobCard.fromFirestore for every user — restore them.
          final payload = item.collection == Collections.jobCards
              ? _restoreJobCardTimestamps(item.data)
              : item.data;

          if (item.operation == 'create' ||
              item.operation == 'update' ||
              item.operation == 'set') {
            await docRef.set(
              payload,
              SetOptions(merge: item.operation == 'update'),
            );
          } else if (item.operation == 'delete') {
            await docRef.delete();
          }
        }

        final wasteLoadId = item.collection.startsWith('waste_')
            ? _loadIdFromWasteQueueItem(item)
            : null;
        await item.delete();
        _clearQueueLastError(item);
        if (wasteLoadId != null) {
          await _maybeClearCollectionMarkerIfQueueDrained(wasteLoadId);
        }
        debugPrint('✅ Synced from queue: ${item.operation} ${item.collection}');
      } catch (e) {
        debugPrint('❌ Failed to sync item: $e');
        _setQueueLastError(item, e);
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

  /// True when any queued waste op still references [loadId] (loads doc id,
  /// item load_id, photo/signature loadId, or stock load_id update).
  bool hasQueuedWasteOpsForLoad(String loadId) {
    try {
      if (!_queueBox.isOpen || loadId.isEmpty) return false;
      for (final item in _queueBox.values) {
        if (!item.collection.startsWith('waste_')) continue;
        if (item.collection == Collections.wasteLoads && item.id == loadId) {
          return true;
        }
        if (item.collection == 'waste_photos' ||
            item.collection == 'waste_signatures') {
          if (item.data['loadId'] == loadId) return true;
          continue;
        }
        if (item.data['load_id'] == loadId || item.data['loadId'] == loadId) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool _loadStatusPastCollection(String? status) {
    return status == 'pending_weighbridge' ||
        status == 'pending_cost_review' ||
        status == 'completed';
  }

  Future<void> _maybeClearCollectionMarkerAfterLoadSync(
    String loadId,
    Map<String, dynamic> data,
  ) async {
    final status = data['status'] as String?;
    if (!_loadStatusPastCollection(status)) return;
    await _maybeClearCollectionMarkerIfQueueDrained(loadId);
  }

  String? _loadIdFromWasteQueueItem(SyncQueueItem item) {
    if (item.collection == Collections.wasteLoads) return item.id;
    return (item.data['loadId'] as String?) ?? (item.data['load_id'] as String?);
  }

  Future<void> _maybeClearCollectionMarkerIfQueueDrained(String loadId) async {
    if (loadId.isEmpty || hasQueuedWasteOpsForLoad(loadId)) return;
    if (await WasteCollectionMarker.hasMarker(loadId)) {
      await WasteCollectionMarker.clearMarker(loadId);
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
        final errorKey = _queueErrorKey(item.collection, item.id);
        details.add({
          'id': item.id,
          'type': type,
          'loadRef': loadRef,
          'age': age,
          'createdAt': item.createdAt,
          'collection': item.collection,
          'operation': item.operation,
          if (_queueLastErrors.containsKey(errorKey))
            'lastError': _queueLastErrors[errorKey],
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

  bool _needsWasteLoadNumber(String? loadNumber) {
    if (loadNumber == null || loadNumber.trim().isEmpty) return true;
    if (_properLoadNumber.hasMatch(loadNumber)) return false;
    if (_legacyLoadNumber.hasMatch(loadNumber)) return false;
    return loadNumber.startsWith('OFFLINE-');
  }

  String? _loadDateForNumbering(Map<String, dynamic> data) {
    final dateTime = data['date_time'];
    if (dateTime is String && dateTime.isNotEmpty) return dateTime;
    final createdAt = data['createdAt'];
    if (createdAt is String && createdAt.isNotEmpty) return createdAt;
    final date = data['date'];
    if (date is String && date.isNotEmpty) return date;
    return null;
  }

  /// Replaces provisional OFFLINE-* numbers with atomic W-NNNN numbers via CF.
  Future<void> _assignWasteLoadNumberIfNeeded(
    String loadId,
    Map<String, dynamic> data,
  ) async {
    final loadNumber = data['load_number'] as String?;
    if (!_needsWasteLoadNumber(loadNumber)) return;

    final callable = _functions.httpsCallable('assignWasteLoadNumber');
    final payload = <String, dynamic>{'loadId': loadId};
    final date = _loadDateForNumbering(data);
    if (date != null) payload['date'] = date;

    final result = await callable.call(payload);
    final assigned = (result.data as Map?)?['load_number'] as String?;
    debugPrint(
      assigned != null
          ? '✅ Assigned waste load number $assigned for $loadId'
          : '✅ Waste load number confirmed for $loadId',
    );
  }

  /// Handles a queued waste photo upload from the central Hive queue.
  /// Uploads the local file to Storage under a deterministic name derived
  /// from the queue item id — retries reuse the same object and URL, making
  /// the arrayUnion patch genuinely idempotent — then patches the target doc,
  /// recomputes the parent load's photo_count, and deletes the local file.
  /// Only the caller (inside try of _processQueue) will delete the queue item on success.
  Future<void> _processWastePhotoUpload(SyncQueueItem item) async {
    final data = item.data;
    final String? localPath = data['localPath'] as String?;
    final String? loadId = data['loadId'] as String?;
    final String? itemId = data['itemId'] as String?;
    final String? targetCollectionOverride = data['targetCollection'] as String?;

    if (localPath == null || loadId == null) {
      debugPrint('⚠️ Invalid waste_photos queue entry, skipping: ${item.id}');
      return; // returning normally lets the caller delete the malformed entry
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('⚠️ Local photo no longer exists for queue item ${item.id}: $localPath');
      // Surface the permanent loss, then allow delete so we don't retry forever.
      await _logWasteMediaLostAudit(item, mediaType: 'photo');
      return;
    }

    // Deterministic per-queue-item filename: a retry after an ambiguous
    // failure re-uploads to the same object instead of minting a duplicate.
    final fileName = '${item.id}.jpg';
    final String storageFolder;
    final String targetCollection;
    final String targetDocId;
    final String photoField;
    if (targetCollectionOverride == Collections.wasteStock && itemId != null) {
      storageFolder = 'waste_stock/$itemId';
      targetCollection = Collections.wasteStock;
      targetDocId = itemId;
      photoField = 'photos';
    } else if (itemId != null) {
      storageFolder = 'waste_items/$itemId';
      targetCollection = Collections.wasteItems;
      targetDocId = itemId;
      photoField = 'photos';
    } else {
      storageFolder = 'waste_loads/$loadId';
      targetCollection = Collections.wasteLoads;
      targetDocId = loadId;
      photoField = 'load_photos';
    }
    final storagePath = '$storageFolder/photos/$fileName';

    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final snapshot = await ref.putFile(file);
    final downloadUrl = await snapshot.ref.getDownloadURL();

    // Patch the target document (load or item) - arrayUnion is idempotent-friendly

    await FirebaseFirestore.instance
        .collection(targetCollection)
        .doc(targetDocId)
        .update({
      photoField: FieldValue.arrayUnion([downloadUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // The queue owns the file — remove it now that the upload landed.
    try {
      await file.delete();
    } catch (_) {}

    // Keep the load's photo_count (displayed in Pulse) in sync with the
    // arrays this late upload just changed. waste_stock has no parent load.
    if (targetCollection != Collections.wasteStock) {
      await _recomputeWastePhotoCount(loadId);
    }

    debugPrint('✅ Waste photo synced from queue → $targetCollection/$targetDocId');
    // Success: _processQueue will delete the item after this returns without throw
  }

  /// Best-effort audit record for a queued photo/signature whose local file
  /// was permanently lost (e.g. cache cleared) before it could sync. Shape
  /// mirrors WasteService.logWasteTypeOverrideAudit. Never throws — the
  /// queue entry must still drain.
  Future<void> _logWasteMediaLostAudit(
    SyncQueueItem item, {
    required String mediaType,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('waste_audit').add({
        'action': 'media_lost',
        'media_type': mediaType,
        'load_id': item.data['loadId'],
        if (item.data['itemId'] != null) 'item_id': item.data['itemId'],
        'local_path': item.data['localPath'],
        'queued_at': Timestamp.fromDate(item.createdAt),
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ media_lost audit write failed (non-fatal): $e');
    }
  }

  /// Recomputes a load's photo_count from truth (load_photos + item photos)
  /// and writes the absolute value. Used after late photo uploads and after
  /// replaying a queued waste_loads write that carried a stale absolute
  /// photo_count. Best-effort: a failed recompute must never resurrect an
  /// already-uploaded photo's queue entry.
  Future<void> _recomputeWastePhotoCount(String loadId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final loadRef = firestore.collection(Collections.wasteLoads).doc(loadId);
      final loadSnap = await loadRef.get();
      if (!loadSnap.exists) return;
      final loadPhotos =
          (loadSnap.data()?['load_photos'] as List?)?.length ?? 0;
      final itemsSnap = await firestore
          .collection(Collections.wasteItems)
          .where('load_id', isEqualTo: loadId)
          .get();
      var itemPhotos = 0;
      for (final doc in itemsSnap.docs) {
        final d = doc.data();
        if (d['is_deleted'] == true) continue;
        itemPhotos += (d['photos'] as List?)?.length ?? 0;
      }
      await loadRef.update({'photo_count': loadPhotos + itemPhotos});
    } catch (e) {
      debugPrint('⚠️ photo_count recompute failed for $loadId (non-fatal): $e');
    }
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
      return; // returning normally lets the caller delete the malformed entry
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('⚠️ Local signature file no longer exists for queue item ${item.id}: $localPath');
      // Surface the permanent loss, then allow delete so we don't retry forever.
      await _logWasteMediaLostAudit(item, mediaType: 'signature');
      return;
    }

    final bytes = await file.readAsBytes();

    // Deterministic per-queue-item filename (see _processWastePhotoUpload) —
    // retries overwrite the same object instead of minting duplicates.
    final fileName = 'signature_${item.id}.png';
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
          // Queue-owned media file goes with the entry. The path guard keeps
          // cache originals (still shown by screens) safe.
          final localPath = item.data['localPath'] as String?;
          if (localPath != null &&
              localPath.contains(wasteMediaQueueDirName)) {
            try {
              await File(localPath).delete();
            } catch (_) {}
          }
          await item.delete();
          _clearQueueLastError(item);
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
                final payload = _restoreWastePayload(item.collection, item.data);
                if (item.operation == 'create' ||
                    item.operation == 'update' ||
                    item.operation == 'set') {
                  await docRef.set(payload, SetOptions(merge: true));
                  if (item.collection == Collections.wasteLoads) {
                    if (item.data.containsKey('photo_count') ||
                        item.data.containsKey('load_photos') ||
                        _loadStatusPastCollection(item.data['status'] as String?)) {
                      await _recomputeWastePhotoCount(item.id);
                    }
                    await _maybeClearCollectionMarkerAfterLoadSync(
                      item.id,
                      item.data,
                    );
                  }
                } else if (item.operation == 'delete') {
                  await docRef.delete();
                }
                succeeded = true;
              }
            } else {
              final docRef = FirebaseFirestore.instance.collection(item.collection).doc(item.id);
              if (item.operation == 'create' ||
                  item.operation == 'update' ||
                  item.operation == 'set') {
                await docRef.set(item.data, SetOptions(merge: true));
              } else if (item.operation == 'delete') {
                await docRef.delete();
              }
              succeeded = true;
            }
          } catch (e) {
            debugPrint('❌ Targeted per-item retry failed for ${item.collection}/${item.id}: $e');
            _setQueueLastError(item, e);
            succeeded = false;
          }

          if (succeeded) {
            await item.delete();
            _clearQueueLastError(item);
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

  int getQueuedFleetOperationCount() {
    try {
      if (!_queueBox.isOpen) return 0;
      return _queueBox.values
          .where((item) => item.collection.startsWith('fleet_'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// Per-item view of queued fleet operations for FleetQueuedScreen.
  /// Mirrors getQueuedWasteDetails: friendly type, reference, relative age.
  /// Sorted newest-first; safe no-op when the box isn't open.
  List<Map<String, dynamic>> getQueuedFleetDetails() {
    try {
      if (!_queueBox.isOpen) return [];
      final now = DateTime.now();
      final details = <Map<String, dynamic>>[];
      for (final item in _queueBox.values) {
        if (!item.collection.startsWith('fleet_')) continue;
        String type;
        String? ref;
        if (item.collection == 'fleet_photos') {
          type = 'Photo upload';
          ref = (item.data['targetKind'] as String?) == 'work_record'
              ? 'for a work record'
              : 'for a problem report';
        } else if (item.collection == Collections.fleetWorkRecords &&
            item.operation == 'create_cf') {
          type = 'Work record';
          ref = (item.data['title'] as String?) ??
              (item.data['asset_name'] as String?);
        } else if (item.collection == Collections.fleetWorkRecords) {
          type = 'Work record update';
          ref = (item.data['title'] as String?) ??
              (item.data['asset_name'] as String?);
        } else if (item.collection == Collections.fleetIssues) {
          type = 'Problem report';
          ref = (item.data['asset_name'] as String?) ??
              (item.data['description'] as String?);
        } else if (item.collection == Collections.fleetDailyChecks) {
          type = item.operation == 'update' ? 'End shift check' : 'Daily check';
          ref = (item.data['asset_name'] as String?);
        } else {
          type = 'Other (${item.collection.substring('fleet_'.length)})';
          ref = null;
        }
        final errorKey = _queueErrorKey(item.collection, item.id);
        details.add({
          'id': item.id,
          'type': type,
          'ref': ref,
          'age': _formatRelativeAge(now, item.createdAt),
          'createdAt': item.createdAt,
          'collection': item.collection,
          'operation': item.operation,
          if (_queueLastErrors.containsKey(errorKey))
            'lastError': _queueLastErrors[errorKey],
        });
      }
      details.sort((a, b) =>
          (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));
      return details;
    } catch (_) {
      return [];
    }
  }

  /// Targeted retry for a single queued fleet item (FleetQueuedScreen).
  /// On success: deletes the queue entry. On failure: records [lastError].
  Future<bool> retrySpecificQueuedFleetItem(Map<String, dynamic> detail) async {
    try {
      if (!_queueBox.isOpen) return false;
      final targetId = detail['id'] as String?;
      final targetCollection = detail['collection'] as String?;
      final targetOp = detail['operation'] as String?;
      final targetCreated = detail['createdAt'] as DateTime?;

      for (final item in _queueBox.values.toList()) {
        if (item.collection != targetCollection ||
            item.id != targetId ||
            item.operation != targetOp ||
            (targetCreated != null && item.createdAt != targetCreated)) {
          continue;
        }
        try {
          await _processFleetQueueItem(
              item, FirebaseFirestore.instance);
          await item.delete();
          _clearQueueLastError(item);
          debugPrint(
              '✅ Fleet targeted retry succeeded: ${item.collection}/${item.id}');
          return true;
        } catch (e) {
          debugPrint(
              '❌ Fleet targeted retry failed for ${item.collection}/${item.id}: $e');
          _setQueueLastError(item, e);
          return false;
        }
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ retrySpecificQueuedFleetItem error: $e');
      return false;
    }
  }

  Future<void> _processFleetQueueItem(
    SyncQueueItem item,
    FirebaseFirestore firestore,
  ) async {
    if (item.collection == 'fleet_photos' && item.operation == 'upload') {
      await _processFleetPhotoUpload(item);
    } else if (item.collection == Collections.fleetWorkRecords &&
        item.operation == 'create_cf') {
      await _processFleetWorkRecordCreate(item);
    } else {
      final docRef = firestore.collection(item.collection).doc(item.id);
      final payload = _restoreFleetTimestamps(item.data);
      if (item.operation == 'create') {
        final existing = await docRef.get();
        if (!existing.exists) {
          await docRef.set(payload);
        }
      } else if (item.operation == 'update' || item.operation == 'set') {
        await docRef.set(
          payload,
          SetOptions(merge: item.operation == 'update'),
        );
      } else if (item.operation == 'delete') {
        await docRef.delete();
      }
    }
  }

  Future<void> removeQueuedItem({
    required String collection,
    required String documentId,
  }) async {
    try {
      if (!_queueBox.isOpen) return;
      for (final item in _queueBox.values.toList()) {
        if (item.collection == collection && item.id == documentId) {
          await item.delete();
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ removeQueuedItem error: $e');
    }
  }

  /// Mutates the data map of one queued item in place and persists it.
  /// Used to record partial progress (e.g. the CF-created record id, photo
  /// paths already uploaded) so a replay resumes instead of repeating work.
  Future<void> mutateQueuedItemData({
    required String collection,
    required String documentId,
    required void Function(Map<String, dynamic> data) mutate,
  }) async {
    try {
      if (!_queueBox.isOpen) return;
      for (final item in _queueBox.values.toList()) {
        if (item.collection == collection && item.id == documentId) {
          mutate(item.data);
          await item.save();
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ mutateQueuedItemData error: $e');
    }
  }

  static Map<String, dynamic> _restoreFirestoreTimestamps(
    Map<String, dynamic> data,
  ) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'created_at' ||
          key == 'createdAt' ||
          key == 'updated_at' ||
          key == 'updatedAt') {
        if (value is String) {
          result[key] = FieldValue.serverTimestamp();
        } else {
          result[key] = value;
        }
      } else if (value is Map<String, dynamic>) {
        result[key] = _restoreFirestoreTimestamps(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Routes a queued waste payload through the right timestamp restorer for
  /// its collection. waste_photos/waste_signatures never reach here (they are
  /// handled by the upload processors before this dispatch).
  static Map<String, dynamic> _restoreWastePayload(
    String collection,
    Map<String, dynamic> data,
  ) {
    if (collection == Collections.wasteStock) {
      return _restoreFirestoreTimestamps(data);
    }
    if (collection == Collections.wasteLoads) {
      return _restoreWasteLoadTimestamps(data);
    }
    if (collection == Collections.wasteItems) {
      return _restoreWasteItemTimestamps(data);
    }
    return data;
  }

  /// Every Timestamp-typed date field on a waste_loads document (see
  /// WasteLoad.toFirestore). Queue sanitisation turned these into ISO-8601
  /// strings; replaying them verbatim stores strings in Firestore, and
  /// Firestore orders by TYPE first — string-dated loads silently fall out of
  /// every Timestamp range query (Pulse reports, board metrics, the 14-day
  /// home window). The sanitized string IS the real capture time, so restore
  /// with Timestamp.fromDate — NOT serverTimestamp.
  static const Set<String> _wasteLoadTimestampKeys = {
    'date_time',
    'scheduled_for',
    'completed_at',
    'cost_reviewed_at',
    'weighbridge_received_at',
    'pending_cost_review_at',
    'pending_weighbridge_at',
    'weighbridge_ticket_waived_at',
    'createdAt',
  };

  /// Visible for the offline-resilience tests.
  static Map<String, dynamic> restoreWasteLoadTimestamps(
          Map<String, dynamic> data) =>
      _restoreWasteLoadTimestamps(data);

  /// Visible for the offline-resilience tests.
  static Map<String, dynamic> restoreWasteItemTimestamps(
          Map<String, dynamic> data) =>
      _restoreWasteItemTimestamps(data);

  static Map<String, dynamic> _restoreWasteLoadTimestamps(
    Map<String, dynamic> data,
  ) =>
      _restoreTimestampsByKeys(data, _wasteLoadTimestampKeys);

  static Map<String, dynamic> _restoreWasteItemTimestamps(
    Map<String, dynamic> data,
  ) =>
      _restoreTimestampsByKeys(data, const {'createdAt'});

  /// ISO string → Timestamp for the given keys; updatedAt/updated_at →
  /// serverTimestamp (they mean "when this landed"). Unparseable strings pass
  /// through unchanged — never destroy waste data (job cards null them, but a
  /// waste load's dates feed legal/reporting flows). Top-level keys only.
  static Map<String, dynamic> _restoreTimestampsByKeys(
    Map<String, dynamic> data,
    Set<String> keys,
  ) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if ((key == 'updatedAt' || key == 'updated_at') && value is String) {
        result[key] = FieldValue.serverTimestamp();
      } else if (keys.contains(key) && value is String) {
        final parsed = DateTime.tryParse(value);
        result[key] = parsed != null ? Timestamp.fromDate(parsed) : value;
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Every Timestamp-typed field on a job card document. Queue sanitisation
  /// converts these to ISO-8601 strings for Hive; replay MUST convert them
  /// back or the stored doc breaks JobCard.fromFirestore for all users.
  static const Set<String> _jobCardTimestampKeys = {
    'createdAt',
    'assignedAt',
    'startedAt',
    'lastUpdatedAt',
    'notificationReceivedAt',
    'notifiedAtStage1',
    'notifiedAtStage2',
    'notifiedAtStage3',
    'notifiedAtStage4',
    'completedAt',
    'monitoringStartedAt',
    'closedAt',
  };

  /// Restores Firestore types on a queued job-card payload:
  ///  - known timestamp fields: ISO string → [Timestamp]
  ///    (`lastUpdatedAt` → serverTimestamp, since it means "when this landed")
  ///  - assignmentHistory entries: string `timestamp` → [Timestamp]
  /// Visible for the offline-resilience tests.
  static Map<String, dynamic> restoreJobCardTimestamps(
          Map<String, dynamic> data) =>
      _restoreJobCardTimestamps(data);

  static Map<String, dynamic> _restoreJobCardTimestamps(
    Map<String, dynamic> data,
  ) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'lastUpdatedAt' && value is String) {
        result[key] = FieldValue.serverTimestamp();
      } else if (_jobCardTimestampKeys.contains(key) && value is String) {
        final parsed = DateTime.tryParse(value);
        result[key] = parsed != null ? Timestamp.fromDate(parsed) : null;
      } else if (key == 'assignmentHistory' && value is List) {
        result[key] = value.map((e) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final ts = m['timestamp'];
            if (ts is String) {
              final parsed = DateTime.tryParse(ts);
              if (parsed != null) m['timestamp'] = Timestamp.fromDate(parsed);
            }
            return m;
          }
          return e;
        }).toList();
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  static const Set<String> _workReportTimestampKeys = {
    'periodStart',
    'periodEnd',
    'pdfGeneratedAt',
    'jobLinesRefreshedAt',
    'lastUpdatedAt',
    'createdAt',
    'updatedAt',
    'workDate',
    'editedAt',
  };

  static Map<String, dynamic> _restoreWorkReportTimestamps(
    Map<String, dynamic> data,
  ) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if ((key == 'lastUpdatedAt' || key == 'updatedAt' || key == 'createdAt') &&
          value is String) {
        result[key] = FieldValue.serverTimestamp();
      } else if (_workReportTimestampKeys.contains(key) && value is String) {
        final parsed = DateTime.tryParse(value);
        result[key] = parsed != null ? Timestamp.fromDate(parsed) : null;
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Fleet replay payloads: created_at/updatedAt become serverTimestamp (via
  /// [_restoreFirestoreTimestamps]) and `*_date` fields sanitized to ISO
  /// strings become Timestamps again — fleet queries filter and order on
  /// cost_date, and a string there would silently drop the doc from results.
  static Map<String, dynamic> _restoreFleetTimestamps(
    Map<String, dynamic> data,
  ) {
    final base = _restoreFirestoreTimestamps(data);
    final result = <String, dynamic>{};
    for (final entry in base.entries) {
      final value = entry.value;
      if (entry.key.endsWith('_date') && value is String) {
        final parsed = DateTime.tryParse(value);
        result[entry.key] = parsed != null ? Timestamp.fromDate(parsed) : value;
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  Future<void> _processFleetPhotoUpload(SyncQueueItem item) async {
    final data = item.data;
    final localPath = data['localPath'] as String?;
    final targetKind = data['targetKind'] as String?;
    final targetId = data['targetId'] as String?;

    if (localPath == null || targetKind == null || targetId == null) {
      debugPrint('⚠️ Invalid fleet_photos queue entry, skipping: ${item.id}');
      return;
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('⚠️ Fleet photo missing for queue item ${item.id}: $localPath');
      return;
    }

    final collection = targetKind == 'work_record'
        ? Collections.fleetWorkRecords
        : Collections.fleetIssues;
    final storageFolder = targetKind == 'work_record'
        ? 'fleet_work_records/$targetId'
        : 'fleet_issues/$targetId';
    final fileName = '${const Uuid().v4()}.jpg';
    final ref = FirebaseStorage.instance.ref('$storageFolder/photos/$fileName');
    final snapshot = await ref.putFile(file);
    final downloadUrl = await snapshot.ref.getDownloadURL();

    await FirebaseFirestore.instance.collection(collection).doc(targetId).update({
      'photos': FieldValue.arrayUnion([downloadUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('✅ Fleet photo synced → $collection/$targetId');
  }

  Future<void> _processFleetWorkRecordCreate(SyncQueueItem item) async {
    final raw = Map<String, dynamic>.from(item.data);
    final createdRecordId = raw.remove('_created_record_id') as String?;
    final photoPaths =
        (raw.remove('_pending_photo_paths') as List?)?.cast<String>() ?? [];
    final partsRaw = raw.remove('_parts');
    final linkedIssueIds =
        (raw.remove('_linked_issue_ids') as List?)?.cast<String>() ?? [];
    final resolverClock = raw.remove('_resolver_clock_no') as String? ?? '';
    final resolverName = raw.remove('_resolver_name') as String? ?? '';

    // Only call the CF when no record exists yet for this queue item. The
    // queue id doubles as the CF idempotency key (client_ref → document ID),
    // so even a lost response cannot mint a duplicate work number.
    String recordId;
    if (createdRecordId != null) {
      recordId = createdRecordId;
    } else {
      raw.putIfAbsent('client_ref', () => item.id);
      final callable = _functions.httpsCallable('createFleetWorkRecord');
      final result = await callable.call(raw);
      final resultData = Map<String, dynamic>.from(result.data as Map);
      if (resultData['success'] != true) {
        throw Exception(resultData['error'] ?? 'createFleetWorkRecord failed');
      }
      recordId = resultData['id'] as String;
      item.data['_created_record_id'] = recordId;
      await item.save();
    }

    for (final path in photoPaths) {
      final file = File(path);
      if (file.existsSync()) {
        final fileName = '${const Uuid().v4()}.jpg';
        final ref = FirebaseStorage.instance
            .ref('fleet_work_records/$recordId/photos/$fileName');
        final snapshot = await ref.putFile(file);
        final url = await snapshot.ref.getDownloadURL();
        await FirebaseFirestore.instance
            .collection(Collections.fleetWorkRecords)
            .doc(recordId)
            .update({
          'photos': FieldValue.arrayUnion([url]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      // Persist progress per photo so a crash mid-batch never re-uploads
      // (or retries a deleted temp file).
      (item.data['_pending_photo_paths'] as List?)?.remove(path);
      await item.save();
    }

    if (partsRaw is List && partsRaw.isNotEmpty) {
      final partsRef = FirebaseFirestore.instance
          .collection(Collections.fleetWorkRecords)
          .doc(recordId)
          .collection(Collections.fleetWorkParts);
      // Replace rather than append so a partial earlier replay can't
      // duplicate parts.
      final existing = await partsRef.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      for (final part in partsRaw) {
        if (part is Map) {
          batch.set(partsRef.doc(), {
            'part_name': part['part_name'],
            if (part['quantity'] != null) 'quantity': part['quantity'],
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
      item.data.remove('_parts');
      await item.save();
    }

    for (final issueId in linkedIssueIds) {
      await FirebaseFirestore.instance
          .collection(Collections.fleetIssues)
          .doc(issueId)
          .update({
        'status': 'resolved',
        'resolution_type': 'work_record',
        'linked_work_record_id': recordId,
        'resolved_by_clock_no': resolverClock,
        'resolved_by_name': resolverName,
        'resolved_at': FieldValue.serverTimestamp(),
      });
    }

    debugPrint('✅ Fleet work record synced via CF → $recordId');
  }

  // ---------------------------------------------------------------------------
  // SITE SECURITY queue processing
  // ---------------------------------------------------------------------------

  bool _needsSecurityEntryNumber(String? entryNumber) {
    if (entryNumber == null || entryNumber.trim().isEmpty) return true;
    if (_properSecurityEntryNumber.hasMatch(entryNumber)) return false;
    return entryNumber.startsWith('OFFLINE-SEC-');
  }

  Future<void> _assignSecurityEntryNumberIfNeeded(
    String entryId,
    Map<String, dynamic> data,
  ) async {
    final entryNumber = data['entry_number'] as String?;
    if (!_needsSecurityEntryNumber(entryNumber)) return;

    final callable = _functions.httpsCallable('assignSecurityEntryNumber');
    final result = await callable.call({'entryId': entryId});
    final assigned = (result.data as Map?)?['entry_number'] as String?;
    debugPrint(
      assigned != null
          ? '✅ Assigned security entry number $assigned for $entryId'
          : '✅ Security entry number confirmed for $entryId',
    );
  }

  Future<void> _processSecurityQueueItem(
    SyncQueueItem item,
    FirebaseFirestore firestore,
  ) async {
    if (item.collection == 'security_photos' && item.operation == 'upload') {
      await _processSecurityPhotoUpload(item);
    } else if (item.collection == Collections.securityEntries &&
        item.operation == 'create_cf') {
      await _processSecurityEntryCreate(item);
    } else {
      final docRef = firestore.collection(item.collection).doc(item.id);
      final payload = _restoreFirestoreTimestamps(item.data);
      if (item.operation == 'create' ||
          item.operation == 'update' ||
          item.operation == 'set') {
        await docRef.set(
          payload,
          SetOptions(merge: item.operation == 'update'),
        );
        if (item.collection == Collections.securityEntries &&
            (item.operation == 'set' || item.operation == 'create')) {
          await _assignSecurityEntryNumberIfNeeded(item.id, item.data);
        }
      } else if (item.operation == 'delete') {
        await docRef.delete();
      }
    }
  }

  Future<void> _processSecurityPhotoUpload(SyncQueueItem item) async {
    final data = item.data;
    final String? localPath = data['localPath'] as String?;
    final String? entryId = data['entryId'] as String?;

    if (localPath == null || entryId == null) {
      debugPrint('⚠️ Invalid security_photos queue entry, skipping: ${item.id}');
      return;
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint(
          '⚠️ Local security photo no longer exists for queue item ${item.id}');
      return;
    }

    final fileName = '${const Uuid().v4()}.jpg';
    final storagePath = 'security_entries/$entryId/$fileName';
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final snapshot = await ref.putFile(file);
    final downloadUrl = await snapshot.ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection(Collections.securityEntries)
        .doc(entryId)
        .update({
      'photos': FieldValue.arrayUnion([downloadUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('✅ Security photo synced from queue → security_entries/$entryId');
  }

  Future<void> _processSecurityEntryCreate(SyncQueueItem item) async {
    final raw = Map<String, dynamic>.from(item.data);
    final createdEntryId = raw.remove('_created_entry_id') as String?;
    final photoPaths =
        (raw.remove('_pending_photo_paths') as List?)?.cast<String>() ?? [];

    String entryId;
    if (createdEntryId != null) {
      entryId = createdEntryId;
    } else {
      raw.putIfAbsent('client_ref', () => item.id);
      final callable = _functions.httpsCallable('createSecurityEntry');
      final result = await callable.call(raw);
      final resultData = Map<String, dynamic>.from(result.data as Map);
      if (resultData['success'] != true) {
        throw Exception(resultData['error'] ?? 'createSecurityEntry failed');
      }
      entryId = resultData['id'] as String;
      item.data['_created_entry_id'] = entryId;
      await item.save();
    }

    for (final path in photoPaths) {
      final file = File(path);
      if (file.existsSync()) {
        final fileName = '${const Uuid().v4()}.jpg';
        final ref = FirebaseStorage.instance
            .ref('security_entries/$entryId/$fileName');
        final snapshot = await ref.putFile(file);
        final url = await snapshot.ref.getDownloadURL();
        await FirebaseFirestore.instance
            .collection(Collections.securityEntries)
            .doc(entryId)
            .update({
          'photos': FieldValue.arrayUnion([url]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      (item.data['_pending_photo_paths'] as List?)?.remove(path);
      await item.save();
    }

    debugPrint('✅ Security entry synced via CF → $entryId');
  }
}