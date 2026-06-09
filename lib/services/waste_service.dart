import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import 'sync_service.dart';
import '../models/contractor.dart';
import '../models/waste_settings.dart';
import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';

/// Service for all WasteTrack (Waste Management) operations.
/// Designed to be used from Riverpod providers and screens.
///
/// Photo strategy (reuses patterns from create_job_card_screen & job_card_detail_screen):
/// - Pick + heavy compress (camera or gallery)
/// - Local temp file until upload
/// - Upload to Storage under `waste/{loadId or itemId}/photos/...`
/// - Store download URLs in Firestore documents
///
/// Load numbering is handled server-side via the `createWasteLoad` Cloud Function
/// for atomic daily sequence (WT-YYYYMMDD-001).
class WasteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'africa-south1');

  // Session-level offline photo resilience; central Hive queue via SyncService handles cross-session.
  final List<Map<String, dynamic>> _sessionOfflinePhotoQueue = [];

  int get sessionQueuedPhotoCount => _sessionOfflinePhotoQueue.length;

  // Session queue for signature bytes offline resilience (temp file pattern, session-level; mirrors photo flow in this service only)
  final List<Map<String, dynamic>> _sessionOfflineSignatureQueue = [];

  int get sessionQueuedSignatureCount => _sessionOfflineSignatureQueue.length;

  // ---------------------------------------------------------------------------
  // LOAD NUMBERING (via Cloud Function)
  // ---------------------------------------------------------------------------

  /// Creates a new waste load document with an auto-generated load number.
  /// The Cloud Function handles the atomic counter for the current date.
  Future<Map<String, dynamic>> createLoad(Map<String, dynamic> initialData) async {
    try {
      final callable = _functions.httpsCallable('createWasteLoad');
      final result = await callable.call(initialData);
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw Exception('Failed to create waste load via Cloud Function: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD - LOADS
  // ---------------------------------------------------------------------------

  Future<void> updateLoad(String loadId, Map<String, dynamic> data) async {
    await _firestore.collection(Collections.wasteLoads).doc(loadId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Resilient weighbridge entry (core security flow + deviation trigger).
  /// Attempts direct Firestore update; on any failure (offline etc) queues via central SyncService
  /// so the actual weight + deviation audit can land later. Always processes queue after attempt.
  /// Updates local model caller side on optimistic success.
  Future<void> saveWeighbridgeWeight({
    required String loadId,
    required double actualWeightKg,
    String? updatedBy,
  }) async {
    final updateData = {
      'actual_weighbridge_weight_kg': actualWeightKg,
      if (updatedBy != null) 'weighbridge_updated_by': updatedBy,
    };

    try {
      await updateLoad(loadId, updateData);
      // Success path - still queue for audit trail / extra resilience (idempotent)
      await SyncService().addToQueue(
        collection: Collections.wasteLoads,
        operation: 'update',
        data: {
          ...updateData,
          'updatedAt': DateTime.now().toIso8601String(), // client time; server will correct on apply
        },
        documentId: loadId,
      );
    } catch (e) {
      // Offline or transient failure: queue for later processing by central handler
      await SyncService().addToQueue(
        collection: Collections.wasteLoads,
        operation: 'update',
        data: {
          ...updateData,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        documentId: loadId,
      );
    } finally {
      // Always attempt to drain queue (covers reconnect edge cases)
      await SyncService().processNow();
    }
  }

  Future<void> markLoadComplete(String loadId, {
    String? driverSignatureUrl,
    required String completedBy,
  }) async {
    await _firestore.collection(Collections.wasteLoads).doc(loadId).update({
      'status': 'completed',
      if (driverSignatureUrl != null) 'driver_signature_url': driverSignatureUrl,
      'completed_by': completedBy,
      'completed_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> softDeleteLoad(String loadId, String deletedBy) async {
    // In a real implementation we would copy to waste_deleted_loads first.
    // For v1 we simply mark and let a future admin recovery flow handle the archive copy.
    await _firestore.collection(Collections.wasteLoads).doc(loadId).update({
      'is_deleted': true,
      'deleted_by': deletedBy,
      'deleted_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<WasteLoad>> watchLoads({String? status, int limit = 50}) {
    Query query = _firestore
        .collection(Collections.wasteLoads)
        .orderBy('date_time', descending: true)
        .limit(limit);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((d) => WasteLoad.fromFirestore(d))
        .where((l) => !l.isDeleted)
        .toList());
  }

  // ---------------------------------------------------------------------------
  // TWO-PHASE HANDOFF (manager schedules → guard collects → manager weighbridges)
  // ---------------------------------------------------------------------------

  /// Manager creates a shell load. No Cloud Function needed — no load number
  /// is assigned at scheduling time (number assigned when guard submits via [submitCollection]).
  /// [selectedStockIds] are stored on the load doc; stock items are NOT marked loaded
  /// here — that happens in [submitCollection] when the guard confirms them.
  Future<String> createScheduledLoad({
    required String contractorId,
    String? contractorName,
    required String mainWasteType,
    required DateTime scheduledFor,
    required String scheduledBy,
    required String scheduledByName,
    String? scheduledNotes,
    List<String> selectedStockIds = const [],
  }) async {
    final doc = await _firestore.collection(Collections.wasteLoads).add({
      'load_number': '',
      'contractor_id': contractorId,
      if (contractorName != null) 'contractor_name': contractorName,
      'main_waste_type': mainWasteType,
      'date_time': Timestamp.fromDate(scheduledFor),
      'scheduled_for': Timestamp.fromDate(scheduledFor),
      'scheduled_by': scheduledBy,
      'scheduled_by_name': scheduledByName,
      if (scheduledNotes != null && scheduledNotes.isNotEmpty)
        'scheduled_notes': scheduledNotes,
      'status': WasteLoadStatus.scheduled.value,
      'driver_name': '',
      'vehicle_reg': '',
      'load_photos': [],
      'is_deleted': false,
      'created_by': scheduledBy,
      'recorded_weight_kg': 0.0,
      if (selectedStockIds.isNotEmpty) 'selected_stock_ids': selectedStockIds,
    });
    return doc.id;
  }

  /// Stream of all scheduled (not yet collected) loads, ordered by expected date ascending.
  /// Used by guard home screen "Incoming" section.
  Stream<List<WasteLoad>> watchScheduledLoads({int limit = 50}) {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('status', isEqualTo: WasteLoadStatus.scheduled.value)
        .orderBy('scheduled_for', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WasteLoad.fromFirestore(d))
            .where((l) => !l.isDeleted)
            .toList());
  }

  /// Manager cancels a scheduled load before the guard begins collection.
  /// Throws [StateError] if the load is no longer in [scheduled] status.
  Future<void> cancelScheduledLoad(String loadId) async {
    final ref = _firestore.collection(Collections.wasteLoads).doc(loadId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = WasteLoadStatus.fromString(snap.data()?['status'] as String?);
      if (current != WasteLoadStatus.scheduled) {
        throw StateError('Load is no longer scheduled — cannot cancel (current: ${current.value})');
      }
      tx.update(ref, {'status': WasteLoadStatus.cancelled.value, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// Guard submits a completed collection on a scheduled load.
  /// Uses a Firestore transaction to assert the load is still [scheduled] before
  /// writing, preventing double-collection. Then uploads photos/signature and
  /// writes items, using the same offline resilience pattern as [saveCompleteWasteLoad].
  Future<WasteLoad?> getLoad(String loadId) async {
    final doc = await _firestore.collection(Collections.wasteLoads).doc(loadId).get();
    if (!doc.exists) return null;
    return WasteLoad.fromFirestore(doc);
  }

  Future<void> submitCollection({
    required String loadId,
    required String driverName,
    required String vehicleReg,
    required String collectedBy,
    String? collectedByName,
    required List<Map<String, dynamic>> itemsData,
    List<String> itemPhotoPaths = const [],
    String? signatureLocalPath,
  }) async {
    final ref = _firestore.collection(Collections.wasteLoads).doc(loadId);

    // 1. Atomic status transition (prevents double-collection).
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = WasteLoadStatus.fromString(snap.data()?['status'] as String?);
      if (current != WasteLoadStatus.scheduled) {
        throw StateError('Load already started or completed (current: ${current.value})');
      }
      tx.update(ref, {
        'status': WasteLoadStatus.pendingWeighbridge.value,
        'driver_name': driverName,
        'vehicle_reg': vehicleReg,
        'collected_by': collectedBy,
        if (collectedByName != null) 'collected_by_name': collectedByName,
        'pending_weighbridge_at': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // 2. Queue the status update for offline resilience.
    await SyncService().addToQueue(
      collection: Collections.wasteLoads,
      operation: 'update',
      data: {
        'status': WasteLoadStatus.pendingWeighbridge.value,
        'driver_name': driverName,
        'vehicle_reg': vehicleReg,
        'collected_by': collectedBy,
        if (collectedByName != null) 'collected_by_name': collectedByName,
        'pending_weighbridge_at': DateTime.now().toIso8601String(),
      },
      documentId: loadId,
    );

    // 3. Upload signature if provided.
    if (signatureLocalPath != null) {
      try {
        final sigUrl = await uploadSignature(
          signatureBytes: await File(signatureLocalPath).readAsBytes(),
          loadId: loadId,
        );
        await ref.update({'driver_signature_url': sigUrl});
      } catch (_) {
        await SyncService().addToQueue(
          collection: 'waste_signatures',
          operation: 'upload',
          data: {'localPath': signatureLocalPath, 'loadId': loadId},
          documentId: '${loadId}_sig',
        );
      }
    }

    // 4. Upload item photos and write items (reuse existing patterns).
    int totalPhotoCount = 0;
    for (final item in itemsData) {
      final itemRef = _firestore.collection(Collections.wasteItems).doc();
      final photoUrls = <String>[];

      for (final path in (item['localPhotoPaths'] as List<String>? ?? [])) {
        final url = await _resolveItemPhotoUrl(
          path: path,
          loadId: loadId,
          itemId: itemRef.id,
        );
        if (url != null) photoUrls.add(url);
      }

      totalPhotoCount += photoUrls.length;

      final itemData = {
        ...item,
        'load_id': loadId,
        'photos': photoUrls,
        'createdAt': FieldValue.serverTimestamp(),
      }..remove('localPhotoPaths');

      await itemRef.set(itemData);
      await SyncService().addToQueue(
        collection: Collections.wasteItems,
        operation: 'set',
        data: itemData,
        documentId: itemRef.id,
      );
    }

    await ref.update({'photo_count': totalPhotoCount});
    await SyncService().processNow();
  }

  // ---------------------------------------------------------------------------
  // CRUD - ITEMS
  // ---------------------------------------------------------------------------

  Future<String> addItem(WasteItem item) async {
    final doc = await _firestore.collection(Collections.wasteItems).add(item.toFirestore());
    return doc.id;
  }

  Future<void> updateItem(String itemId, Map<String, dynamic> data) async {
    await _firestore.collection(Collections.wasteItems).doc(itemId).update(data);
  }

  Stream<List<WasteItem>> watchItemsForLoad(String loadId) {
    return _firestore
        .collection(Collections.wasteItems)
        .where('load_id', isEqualTo: loadId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WasteItem.fromFirestore(d))
            .where((i) => !i.isDeleted)
            .toList());
  }

  /// Fetches waste_stock items by their IDs (up to 30 via whereIn).
  /// Used by WasteBeginCollectionScreen to pre-populate pre-linked stock.
  Future<List<WasteStockItem>> getStockItemsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    // Firestore whereIn supports up to 30 values; chunk if needed
    final results = <WasteStockItem>[];
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _firestore
          .collection(Collections.wasteStock)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snap.docs.map(WasteStockItem.fromFirestore));
    }
    return results;
  }

  /// Soft-deletes a waste_item. If the item originated from a stock item
  /// (sourceStockId set), the corresponding waste_stock item is reverted to on_site.
  /// Also subtracts the item weight from the parent load's recorded_weight_kg.
  Future<void> deleteWasteItem(String itemId, {String? sourceStockId}) async {
    final itemSnap =
        await _firestore.collection(Collections.wasteItems).doc(itemId).get();
    final data = itemSnap.data();
    if (data == null) return;

    final loadId = data['load_id'] as String?;
    final weightKg = (data['weight_kg'] as num?)?.toDouble() ?? 0.0;
    final stockId = sourceStockId ?? data['source_stock_id'] as String?;

    await _firestore.collection(Collections.wasteItems).doc(itemId).update({
      'is_deleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (loadId != null && weightKg > 0) {
      final loadSnap =
          await _firestore.collection(Collections.wasteLoads).doc(loadId).get();
      final currentRecorded =
          (loadSnap.data()?['recorded_weight_kg'] as num?)?.toDouble() ?? 0.0;
      final nextRecorded = (currentRecorded - weightKg).clamp(0.0, double.infinity);
      await updateLoad(loadId, {'recorded_weight_kg': nextRecorded});
    }

    if (stockId != null) {
      await _firestore.collection(Collections.wasteStock).doc(stockId).update({
        'status': WasteStockStatus.onSite.value,
        'load_id': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Removes a single photo URL from a waste_item and best-effort deletes the Storage object.
  Future<void> removePhotoFromWasteItem({
    required String itemId,
    required String photoUrl,
  }) async {
    await _firestore.collection(Collections.wasteItems).doc(itemId).update({
      'photos': FieldValue.arrayRemove([photoUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (_isRemotePhotoUrl(photoUrl)) {
      try {
        await _storage.refFromURL(photoUrl).delete();
      } catch (_) {
        // Storage file may already be gone; Firestore update is authoritative.
      }
    }
  }

  /// Adds a new waste_item to an already-existing load (post-submission editing).
  /// Photos are uploaded live; failures are queued to the offline queue.
  Future<void> addItemToExistingLoad({
    required String loadId,
    required String subtype,
    required double weightKg,
    int? quantity,
    String? notes,
    required List<String> localPhotoPaths,
    String? sourceStockId,
  }) async {
    final itemRef = _firestore.collection(Collections.wasteItems).doc();
    final photoUrls = <String>[];

    for (final path in localPhotoPaths) {
      final url = await _resolveItemPhotoUrl(
        path: path,
        loadId: loadId,
        itemId: itemRef.id,
      );
      if (url != null) photoUrls.add(url);
    }

    final data = {
      'load_id': loadId,
      'subtype': subtype,
      'weight_kg': weightKg,
      if (quantity != null) 'quantity': quantity,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'photos': photoUrls,
      if (sourceStockId != null) 'source_stock_id': sourceStockId,
      'is_deleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await itemRef.set(data);

    // Keep load's recorded_weight_kg in sync
    final loadSnap = await _firestore.collection(Collections.wasteLoads).doc(loadId).get();
    final currentRecorded = (loadSnap.data()?['recorded_weight_kg'] as num?)?.toDouble() ?? 0.0;
    await updateLoad(loadId, {'recorded_weight_kg': currentRecorded + weightKg});

    await SyncService().addToQueue(
      collection: Collections.wasteItems,
      operation: 'set',
      data: data,
      documentId: itemRef.id,
    );
    await SyncService().processNow();
  }

  // ---------------------------------------------------------------------------
  // PHOTO HANDLING (reused & adapted from Job Cards patterns)
  // ---------------------------------------------------------------------------

  bool _isRemotePhotoUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Upload a local file, or pass through an existing Firebase URL (pre-loaded stock).
  Future<String?> _resolveItemPhotoUrl({
    required String path,
    required String loadId,
    required String itemId,
  }) async {
    if (_isRemotePhotoUrl(path)) return path;
    try {
      return await uploadWastePhoto(
        localPath: path,
        wasteRef: 'waste_items/$itemId',
      );
    } catch (_) {
      await queueOfflineWastePhoto(
        localPath: path,
        loadId: loadId,
        itemId: itemId,
      );
      return null;
    }
  }

  Future<String?> pickAndCompressPhotoFromSource(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return null;

    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      pickedFile.path,
      '${pickedFile.path}_waste_compressed.jpg',
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
    );
    return compressedFile?.path;
  }

  /// Uploads a compressed local photo file to Storage under the waste prefix.
  /// Returns the download URL.
  Future<String> uploadWastePhoto({
    required String localPath,
    required String wasteRef, // e.g. "waste_loads/abc123" or "waste_items/def456"
    String subfolder = 'photos',
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw Exception('Local photo file no longer exists: $localPath');
    }

    final fileName = '${const Uuid().v4()}.jpg';
    final storagePath = '$wasteRef/$subfolder/$fileName';

    final ref = _storage.ref().child(storagePath);

    final snapshot = await ref.putFile(file);
    final downloadUrl = await snapshot.ref.getDownloadURL();
    return downloadUrl;
  }

  // ---------------------------------------------------------------------------
  // MASTER DATA
  // ---------------------------------------------------------------------------

  Stream<List<WasteType>> watchWasteTypes() {
    return _firestore
        .collection(Collections.wasteTypes)
        .snapshots()
        .map((snap) => snap.docs.map((d) => WasteType.fromFirestore(d)).toList());
  }

  Stream<List<Contractor>> watchContractors() {
    return _firestore
        .collection(Collections.wasteContractors)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Contractor.fromFirestore(d)).toList());
  }

  Future<void> addOrUpdateContractor(Contractor contractor) async {
    if (contractor.id != null) {
      await _firestore.collection(Collections.wasteContractors).doc(contractor.id).set(contractor.toFirestore());
    } else {
      await _firestore.collection(Collections.wasteContractors).add(contractor.toFirestore());
    }
  }

  /// Uploads driver signature (PNG bytes) to Storage and returns the download URL.
  /// Enhanced for offline: on failure (e.g. no connectivity), persists bytes to temp file and queues for session recovery (matches photo temp file queuing pattern in WasteService).
  Future<String> uploadSignature({
    required Uint8List signatureBytes,
    required String loadId,
  }) async {
    try {
      return await _uploadSignatureBytesDirect(signatureBytes, loadId);
    } catch (e) {
      final localPath = await _persistSignatureBytesToTemp(signatureBytes);
      await queueOfflineWasteSignature(localPath: localPath, loadId: loadId);
      rethrow;
    }
  }

  // Internal direct upload (no queuing) - used by public API and offline processor.
  Future<String> _uploadSignatureBytesDirect(Uint8List bytes, String loadId) async {
    final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
    final storagePath = 'waste_loads/$loadId/signature/$fileName';
    final ref = _storage.ref().child(storagePath);
    final snapshot = await ref.putData(bytes);
    return await snapshot.ref.getDownloadURL();
  }

  Future<String> _persistSignatureBytesToTemp(Uint8List bytes) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}waste_sig_$ts.png';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Queues a signature (by persisted temp file path) for later upload.
  /// Uses central SyncService (Hive 'waste_signatures') + session queue (full offline resilience, matches photo pattern exactly).
  Future<void> queueOfflineWasteSignature({required String localPath, required String loadId}) async {
    // Central Hive queue for cross-session processing by SyncService (on connectivity return)
    await SyncService().addToQueue(
      collection: 'waste_signatures',
      operation: 'upload',
      data: {
        'localPath': localPath,
        'loadId': loadId,
      },
      documentId: '${loadId}_sig_${DateTime.now().millisecondsSinceEpoch}',
    );
    // Session queue for same-run recovery (processed inside processOfflineWasteQueue)
    _sessionOfflineSignatureQueue.add({
      'localPath': localPath,
      'loadId': loadId,
    });
  }

  /// New offline-aware helper: persist bytes to temp + queue (central + session). Used by detail screen when network unavailable.
  Future<void> queueOfflineWasteSignatureBytes({
    required Uint8List signatureBytes,
    required String loadId,
  }) async {
    final localPath = await _persistSignatureBytesToTemp(signatureBytes);
    await queueOfflineWasteSignature(localPath: localPath, loadId: loadId);
  }

  // ---------------------------------------------------------------------------
  // HIGH-LEVEL PRODUCTION FLOW: Create complete load with items + photos
  // ---------------------------------------------------------------------------

  /// Orchestrates the full creation of a Waste Load + its Items + photo uploads.
  /// This is the key method for making the Create flow production-ready.
  ///
  /// Flow:
  /// 1. Call Cloud Function to get atomic load number + initial load doc.
  /// 2. Upload all pending photos for items (and optional load-level photos).
  /// 3. Batch write the items with real download URLs.
  /// 4. Return the final load id + number.
  ///
  /// This method is designed to be called from the UI after the user taps "Save" or "Mark Complete".
  Future<Map<String, dynamic>> saveCompleteWasteLoad({
    required Map<String, dynamic> loadData,           // initial load fields (no id yet)
    required List<Map<String, dynamic>> itemsData,    // list of item data (may contain local photo paths)
    List<String> loadLevelPhotoPaths = const [],      // optional load overview photos
    String? actorClockNo,                             // for enhanced pilot flag check + usage logging
  }) async {
    final allowed = await isWasteTrackEnabledForCurrentUser(actorClockNo);
    if (!allowed) {
      throw Exception('WasteTrack is currently disabled by feature flag or your account is not in the active pilot group');
    }
    try {
      // Step 1: Get load number + create skeleton load via CF
      // Compute recorded total early from items for accurate deviation checks later (stored on load)
      final double recordedTotal = itemsData.fold<double>(
        0.0,
        (acc, item) => acc + ((item['weight_kg'] as num?)?.toDouble() ?? 0.0),
      );

      final cfResult = await createLoad({
        ...loadData,
        'recorded_weight_kg': recordedTotal, // pass to CF for initial doc if supported
      });
      final String loadId = cfResult['id'];
      final String loadNumber = cfResult['load_number'];

      await logWasteUsage(
        'save_complete_waste_load',
        clockNo: actorClockNo,
        loadId: loadId,
      );

      final String loadRef = 'waste_loads/$loadId';

      // Step 2: Upload load-level photos (if any) — with per-photo offline queuing for full resilience
      final List<String> loadPhotoUrls = [];
      for (final localPath in loadLevelPhotoPaths) {
        try {
          final url = await uploadWastePhoto(
            localPath: localPath,
            wasteRef: loadRef,
          );
          loadPhotoUrls.add(url);
        } catch (e) {
          await queueOfflineWastePhoto(
            localPath: localPath,
            loadId: loadId,
            // itemId null → targets waste_loads + load_photos field in SyncService processor
          );
        }
      }

      // Update load with photo URLs for the ones that succeeded live
      if (loadPhotoUrls.isNotEmpty) {
        await updateLoad(loadId, {'load_photos': loadPhotoUrls});
      }

      // Queue the top-level load document via central sync for full offline resilience (idempotent via merge on replay)
      await SyncService().addToQueue(
        collection: Collections.wasteLoads,
        operation: 'create',
        data: {
          ...loadData,
          'load_number': loadNumber,
          'id': loadId,
          'recorded_weight_kg': recordedTotal,
        },
        documentId: loadId,
      );

      // Step 3: Process items + their photos (allocate IDs early so offline photo queue entries can target the exact item doc for later patching)
      final batch = _firestore.batch();
      final List<Map<String, dynamic>> preparedItems = []; // {itemData, itemRef, localPhotos}

      // Prep pass: allocate stable item IDs upfront (before any photo work)
      for (final rawItem in itemsData) {
        final itemRef = _firestore.collection(Collections.wasteItems).doc();
        final List<String> localPhotos = List<String>.from(rawItem['localPhotos'] ?? []);
        final itemDataBase = Map<String, dynamic>.from(rawItem)
          ..remove('localPhotos')
          ..['load_id'] = loadId
          ..['createdAt'] = FieldValue.serverTimestamp();
        preparedItems.add({
          'itemDataBase': itemDataBase,
          'itemRef': itemRef,
          'localPhotos': localPhotos,
        });
      }

      // Photo + finalize pass (live uploads here; failures go to central queue WITH concrete itemId)
      int totalPhotoCount = loadPhotoUrls.length;
      for (final prep in preparedItems) {
        final itemRef = prep['itemRef'] as DocumentReference;
        final List<String> localPhotos = List<String>.from(prep['localPhotos'] as List);
        final Map<String, dynamic> itemDataBase = Map<String, dynamic>.from(prep['itemDataBase'] as Map);
        final List<String> photoUrls = [];

        final String itemStorageRef = 'waste_items/${itemRef.id}';

        for (final localPath in localPhotos) {
          try {
            final url = await uploadWastePhoto(
              localPath: localPath,
              wasteRef: itemStorageRef,
            );
            photoUrls.add(url);
          } catch (e) {
            await queueOfflineWastePhoto(
              localPath: localPath,
              loadId: loadId,
              itemId: itemRef.id, // critical: enables SyncService processor to patch the correct doc later
            );
          }
        }

        totalPhotoCount += photoUrls.length;

        final itemData = {
          ...itemDataBase,
          'photos': photoUrls,
        };

        batch.set(itemRef, itemData);

        // Queue via central SyncService for resilience (document write survives intermittent connectivity)
        await SyncService().addToQueue(
          collection: Collections.wasteItems,
          operation: 'create',
          data: itemData,
          documentId: itemRef.id,
        );
      }

      await batch.commit();
      await updateLoad(loadId, {'photo_count': totalPhotoCount});

      return {
        'id': loadId,
        'load_number': loadNumber,
        'success': true,
      };
    } catch (e) {
      throw Exception('Failed to save complete waste load: $e');
    }
  }

  // Rates, settings, etc. can be added here as needed.

  // ---------------------------------------------------------------------------
  // PHASE 3 ADMIN TOOLS: Waste Types management (behind isWasteAdmin in UI)
  // ---------------------------------------------------------------------------

  /// Creates a new waste type master record. Admin only (enforced in calling screen).
  Future<String> createWasteType(WasteType type) async {
    try {
      final doc = await _firestore.collection(Collections.wasteTypes).add(type.toFirestore());
      return doc.id;
    } catch (e) {
      throw Exception('Failed to create waste type: $e');
    }
  }

  /// Adds a subtype to an existing waste type (arrayUnion for safety).
  Future<void> addSubtypeToType(String typeId, String newSubtype) async {
    if (newSubtype.trim().isEmpty) return;
    try {
      await _firestore.collection(Collections.wasteTypes).doc(typeId).update({
        'subtypes': FieldValue.arrayUnion([newSubtype.trim()]),
      });
    } catch (e) {
      throw Exception('Failed to add subtype: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // PHASE 3 ADMIN TOOLS: Rates (waste_rates collection)
  // Uses raw maps (no dedicated WasteRate model to avoid new file creation).
  // UI in WasteAdminScreen gates behind isWasteAdmin + shows costs only to admins.
  // ---------------------------------------------------------------------------

  /// Watches all rates. Caller should filter by contractor/subtype as needed.
  Stream<List<Map<String, dynamic>>> watchRates() {
    return _firestore
        .collection(Collections.wasteRates)
        .orderBy('set_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data());
              data['id'] = d.id;
              return data;
            }).toList());
  }

  /// Sets (creates) a rate entry for a contractor + subtype. Overwrites not implemented (add-only for audit).
  Future<void> setRate({
    required String contractorId,
    required String subtype,
    required double costPerKg,
    required String setBy,
  }) async {
    if (contractorId.isEmpty || subtype.isEmpty || costPerKg <= 0) {
      throw Exception('Invalid rate data');
    }
    try {
      await _firestore.collection(Collections.wasteRates).add({
        'contractor_id': contractorId,
        'subtype': subtype,
        'cost_per_kg': costPerKg,
        'set_by': setBy,
        'set_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to set rate: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // PENDING WEIGHBRIDGE QUERY (used by WastePendingWeighbridgeScreen + reports)
  // Client-side post-filter for weighbridge nulls (Firestore null/absent handling varies).
  // ---------------------------------------------------------------------------

  /// Streams loads awaiting manager weighbridge entry.
  /// Uses the [pendingWeighbridge] status set by the guard on [submitCollection].
  Stream<List<WasteLoad>> watchPendingWeighbridge() {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('status', isEqualTo: WasteLoadStatus.pendingWeighbridge.value)
        .orderBy('pending_weighbridge_at', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WasteLoad.fromFirestore(d))
            .where((l) => !l.isDeleted)
            .toList());
  }

  // ---------------------------------------------------------------------------
  // OFFLINE INTEGRATION (PR2-3) — hooks into existing SyncService/Hive
  // ---------------------------------------------------------------------------

  /// Queues a waste photo for later upload when offline using the central SyncService + session queue.
  /// [targetCollection] overrides the default routing in processOfflineWasteQueue; used by
  /// pallet photos so the processor patches waste_pallets instead of waste_items.
  Future<void> queueOfflineWastePhoto({
    required String localPath,
    required String loadId,
    String? itemId,
    String? targetCollection,
  }) async {
    // Central sync
    await SyncService().addToQueue(
      collection: 'waste_photos',
      operation: 'upload',
      data: {
        'localPath': localPath,
        'loadId': loadId,
        'itemId': itemId,
        if (targetCollection != null) 'targetCollection': targetCollection,
      },
      documentId: '${loadId}_${itemId ?? 'load'}_${DateTime.now().millisecondsSinceEpoch}',
    );
    // Session queue for immediate retry in this run
    _sessionOfflinePhotoQueue.add({
      'localPath': localPath,
      'loadId': loadId,
      'itemId': itemId,
      if (targetCollection != null) 'targetCollection': targetCollection,
    });
  }

  /// Processes queued waste photos using the central SyncService queue + session queue.
  /// Now delegates the heavy lifting to SyncService.processNow() which handles Hive waste_photos entries
  /// with real Storage upload + document patching (arrayUnion to photos/load_photos).
  Future<int> processOfflineWasteQueue() async {
    int uploaded = 0;
    // Legacy session queue (lightweight, same-session recovery)
    final toProcess = List.from(_sessionOfflinePhotoQueue);
    for (final entry in toProcess) {
      try {
        final String? targetColl = entry['targetCollection'] as String?;
        final String? itemId = entry['itemId'] as String?;
        final String loadId = entry['loadId'] as String;
        // Determine storage ref and Firestore target
        String refBase;
        String coll;
        String docId;
        String field;
        if (targetColl == Collections.wasteStock && itemId != null) {
          refBase = 'waste_stock/$itemId';
          coll = Collections.wasteStock;
          docId = itemId;
          field = 'photos';
        } else if (itemId != null) {
          refBase = 'waste_items/$itemId';
          coll = Collections.wasteItems;
          docId = itemId;
          field = 'photos';
        } else {
          refBase = 'waste_loads/$loadId';
          coll = Collections.wasteLoads;
          docId = loadId;
          field = 'load_photos';
        }
        final url = await uploadWastePhoto(
          localPath: entry['localPath'] as String,
          wasteRef: refBase,
        );
        // Best-effort immediate patch for session items (central queue path also does this)
        await _firestore.collection(coll).doc(docId).update({
          field: FieldValue.arrayUnion([url]),
        });
        uploaded++;
        _sessionOfflinePhotoQueue.remove(entry);
      } catch (_) {
        // Still offline or failed - keep in queue for next attempt
      }
    }
    // Session signature queue processing (temp file bytes -> Storage -> patch driver_signature_url on load)
    final sigToProcess = List.from(_sessionOfflineSignatureQueue);
    for (final entry in sigToProcess) {
      try {
        final String localPath = entry['localPath'] as String;
        final String loadId = entry['loadId'] as String;
        final file = File(localPath);
        if (!file.existsSync()) {
          _sessionOfflineSignatureQueue.remove(entry);
          continue;
        }
        final bytes = await file.readAsBytes();
        final url = await _uploadSignatureBytesDirect(bytes, loadId);
        await _firestore.collection(Collections.wasteLoads).doc(loadId).update({
          'driver_signature_url': url,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        uploaded++;
        try {
          await file.delete();
        } catch (_) {}
        _sessionOfflineSignatureQueue.remove(entry);
      } catch (_) {
        // keep for next retry
      }
    }
    // Central Hive queue (the real production path for cross-session / full offline resilience)
    await SyncService().processNow();
    return uploaded;
  }

  // ---------------------------------------------------------------------------
  // FEATURE FLAG
  // ---------------------------------------------------------------------------

  Future<bool> getWasteMasterEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('wasteTrackEnabled') ?? true;
  }

  Future<void> setWasteMasterEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wasteTrackEnabled', enabled);
  }

  Future<bool> isWasteTrackEnabledForCurrentUser(String? clockNo) =>
      getWasteMasterEnabled();

  // ---------------------------------------------------------------------------
  // WASTE SETTINGS (Firestore-backed, waste_settings/config)
  // ---------------------------------------------------------------------------

  Future<WasteSettings> getWasteSettings() async {
    final snap = await _firestore
        .collection(Collections.wasteSettings)
        .doc('config')
        .get();
    if (!snap.exists) return WasteSettings.defaults;
    return WasteSettings.fromFirestore(snap);
  }

  Future<void> saveWasteSettings(WasteSettings settings) async {
    await _firestore
        .collection(Collections.wasteSettings)
        .doc('config')
        .set(settings.toFirestore(), SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // ON-SITE STOCK — pre-load stock tracking for any waste type
  // ---------------------------------------------------------------------------

  /// Creates a new on-site waste stock item and uploads its photos.
  /// Returns the Firestore document ID of the created stock item.
  Future<String> addStockItem({
    required WasteStockItem item,
    required List<String> localPhotoPaths,
  }) async {
    final ref = _firestore.collection(Collections.wasteStock).doc();
    final List<String> photoUrls = [];
    for (final path in localPhotoPaths) {
      try {
        final url = await uploadWastePhoto(
          localPath: path,
          wasteRef: 'waste_stock/${ref.id}',
        );
        photoUrls.add(url);
      } catch (_) {
        await queueOfflineWastePhoto(
          localPath: path,
          loadId: ref.id,
          itemId: ref.id,
          targetCollection: Collections.wasteStock,
        );
      }
    }
    final data = {
      ...item.toFirestore(),
      'photos': photoUrls,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    await ref.set(data);
    await SyncService().addToQueue(
      collection: Collections.wasteStock,
      operation: 'set',
      data: data,
      documentId: ref.id,
    );
    await SyncService().processNow();
    return ref.id;
  }

  /// Streams all non-deleted on-site stock items for a given waste type, newest first.
  Stream<List<WasteStockItem>> watchStockOnSite(String wasteType) {
    return _firestore
        .collection(Collections.wasteStock)
        .where('is_deleted', isEqualTo: false)
        .where('waste_type', isEqualTo: wasteType)
        .where('status', isEqualTo: WasteStockStatus.onSite.value)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(WasteStockItem.fromFirestore).toList())
        .handleError((_) => <WasteStockItem>[]);
  }

  /// Links stock items to a load by updating their status to loaded in a single batch.
  Future<void> markStockLoaded(List<String> stockIds, String loadId) async {
    if (stockIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final id in stockIds) {
      batch.update(_firestore.collection(Collections.wasteStock).doc(id), {
        'status': WasteStockStatus.loaded.value,
        'load_id': loadId,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    for (final id in stockIds) {
      await SyncService().addToQueue(
        collection: Collections.wasteStock,
        operation: 'update',
        data: {
          'status': WasteStockStatus.loaded.value,
          'load_id': loadId,
        },
        documentId: id,
      );
    }
    await SyncService().processNow();
  }

  /// Returns the count and total estimated weight of on-site stock for a waste type.
  Future<({int count, double totalEstimatedKg})> getStockSummary(String wasteType) async {
    try {
      final snap = await _firestore
          .collection(Collections.wasteStock)
          .where('is_deleted', isEqualTo: false)
          .where('waste_type', isEqualTo: wasteType)
          .where('status', isEqualTo: WasteStockStatus.onSite.value)
          .get();
      final items = snap.docs.map(WasteStockItem.fromFirestore).toList();
      final total = items.fold<double>(
        0.0, (acc, i) => acc + (i.estimatedWeightKg ?? 0.0));
      return (count: items.length, totalEstimatedKg: total);
    } catch (_) {
      return (count: 0, totalEstimatedKg: 0.0);
    }
  }

  /// Usage logging for audit/analytics. Never throws; safe to call from any waste path.
  Future<void> logWasteUsage(
    String action, {
    String? clockNo,
    String? loadId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final master = await getWasteMasterEnabled();
      if (!master) return; // no logging when fully disabled

      final data = <String, dynamic>{
        'action': action,
        'clockNo': clockNo,
        'loadId': loadId,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': kIsWeb ? 'web' : 'mobile',
        if (metadata != null) ...metadata,
      };
      await _firestore.collection('waste_usage_logs').add(data);

      if (kDebugMode) {
        debugPrint('[WasteLog] action=$action clock=${clockNo ?? 'n/a'} load=${loadId ?? 'n/a'}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WasteLog] write failed (non-fatal): $e');
      }
      // Swallow errors — logging must never impact user or critical flows
    }
  }
}

