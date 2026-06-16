import 'dart:async';
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
import 'connectivity_service.dart';
import 'sync_service.dart';
import '../models/contractor.dart';
import '../models/waste_settings.dart';
import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';

/// Service for all WasteTrack (Waste Management) operations.
///
/// Singleton: all callers share one instance so in-memory session queues
/// (_sessionOfflinePhotoQueue, _sessionOfflineSignatureQueue) stay consistent
/// across screens during a single app session.
class WasteService {
  static final WasteService _instance = WasteService._internal();
  factory WasteService() => _instance;
  WasteService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'africa-south1');

  // Session-level offline photo resilience; central Hive queue via SyncService handles cross-session.
  final List<Map<String, dynamic>> _sessionOfflinePhotoQueue = [];

  int get sessionQueuedPhotoCount => _sessionOfflinePhotoQueue.length;

  // Session queue for signature bytes offline resilience (temp file pattern, session-level; mirrors photo flow in this service only)
  final List<Map<String, dynamic>> _sessionOfflineSignatureQueue = [];

  int get sessionQueuedSignatureCount => _sessionOfflineSignatureQueue.length;

  static const Duration _photoUploadTimeout = Duration(seconds: 12);
  static const Duration _firestoreWriteTimeout = Duration(seconds: 8);
  static const Duration _cloudFunctionTimeout = Duration(seconds: 15);

  Future<bool> _checkOnline() =>
      ConnectivityService().isOnline().catchError((_) => false);

  /// Only enqueue when offline or a direct Firestore write failed.
  Future<void> _enqueueWasteOp({
    required bool shouldQueue,
    required String collection,
    required String operation,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    if (!shouldQueue) return;
    await SyncService().addToQueue(
      collection: collection,
      operation: operation,
      data: data,
      documentId: documentId,
    );
  }

  // ---------------------------------------------------------------------------
  // LOAD NUMBERING (via Cloud Function)
  // ---------------------------------------------------------------------------

  /// Creates a new waste load document with an auto-generated load number.
  /// The Cloud Function handles the atomic counter for the current date.
  Future<Map<String, dynamic>> createLoad(Map<String, dynamic> initialData) async {
    try {
      final callable = _functions.httpsCallable('createWasteLoad');
      final result = await callable
          .call(initialData)
          .timeout(_cloudFunctionTimeout);
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw Exception('Failed to create waste load via Cloud Function: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD - LOADS
  // ---------------------------------------------------------------------------

  Future<({bool queuedOffline})> updateLoad(
      String loadId, Map<String, dynamic> data) async {
    final online = await _checkOnline();

    if (online) {
      try {
        await _firestore
            .collection(Collections.wasteLoads)
            .doc(loadId)
            .update({...data, 'updatedAt': FieldValue.serverTimestamp()})
            .timeout(_firestoreWriteTimeout);
        return (queuedOffline: false);
      } catch (_) {
        // Fall through to queue.
      }
    }

    // Queue path always uses a serializable timestamp — FieldValue.serverTimestamp()
    // cannot be written to Hive and would corrupt the queue entry.
    final now = DateTime.now();
    final serialized = _serializeLoadDataForQueue(
      {...data, 'updatedAt': now.toIso8601String()},
      now,
    );
    await _enqueueWasteOp(
      shouldQueue: true,
      collection: Collections.wasteLoads,
      operation: 'update',
      data: serialized,
      documentId: loadId,
    );
    return (queuedOffline: true);
  }

  /// Off-site weighbridge document capture. Transitions load to [pendingCostReview]
  /// (not completed — admin approves cost in Review tab).
  Future<({bool queuedOffline})> saveWeighbridgeWeight({
    required String loadId,
    required double actualWeightKg,
    String? weighbridgeNumber,
    String? ticketPhotoLocalPath,
    String? updatedBy,
    bool ticketWaived = false,
    String? ticketWaivedBy,
    String? ticketWaivedByName,
  }) async {
    final ref = _firestore.collection(Collections.wasteLoads).doc(loadId);
    final online = await _checkOnline();
    var queuedOffline = !online;
    final now = DateTime.now();

    String? ticketPhotoUrl;
    if (ticketPhotoLocalPath != null) {
      if (queuedOffline) {
        await queueOfflineWastePhoto(localPath: ticketPhotoLocalPath, loadId: loadId);
      } else {
        try {
          ticketPhotoUrl = await uploadWastePhoto(
            localPath: ticketPhotoLocalPath,
            wasteRef: 'waste_loads/$loadId',
            subfolder: 'weighbridge_ticket',
          ).timeout(_photoUploadTimeout);
        } catch (_) {
          await queueOfflineWastePhoto(localPath: ticketPhotoLocalPath, loadId: loadId);
          queuedOffline = true;
        }
      }
    }

    final updateData = {
      'actual_weighbridge_weight_kg': actualWeightKg,
      if (weighbridgeNumber != null && weighbridgeNumber.isNotEmpty)
        'weighbridge_number': weighbridgeNumber,
      if (ticketPhotoUrl != null) 'weighbridge_ticket_photo_url': ticketPhotoUrl,
      'weighbridge_ticket_waived': ticketWaived,
      if (ticketWaived) ...{
        'weighbridge_ticket_waived_by': ticketWaivedBy ?? updatedBy,
        if (ticketWaivedByName != null && ticketWaivedByName.isNotEmpty)
          'weighbridge_ticket_waived_by_name': ticketWaivedByName,
        'weighbridge_ticket_waived_at': now.toIso8601String(),
      },
      'status': WasteLoadStatus.pendingCostReview.value,
      'weighbridge_received_at': now.toIso8601String(),
      'pending_cost_review_at': now.toIso8601String(),
      if (updatedBy != null) 'weighbridge_updated_by': updatedBy,
    };

    var statusAlreadyInReview = false;
    if (online && !queuedOffline) {
      try {
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final current = WasteLoadStatus.fromString(snap.data()?['status'] as String?);
          if (current == WasteLoadStatus.pendingCostReview) {
            statusAlreadyInReview = true;
            return;
          }
          if (current != WasteLoadStatus.pendingWeighbridge) {
            throw StateError(
              'Weighbridge cannot be submitted from status: ${current.value}',
            );
          }
          tx.update(ref, {
            ...updateData,
            'weighbridge_received_at': FieldValue.serverTimestamp(),
            'pending_cost_review_at': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }).timeout(_firestoreWriteTimeout);
      } on StateError {
        rethrow;
      } catch (_) {
        queuedOffline = true;
      }
    }

    await _enqueueWasteOp(
      shouldQueue: queuedOffline && !statusAlreadyInReview,
      collection: Collections.wasteLoads,
      operation: 'update',
      data: updateData,
      documentId: loadId,
    );

    return (queuedOffline: queuedOffline);
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

  /// All non-deleted loads ordered newest-first. Used by the reports screen.
  /// [is_deleted] filtered at the server — does not consume limit on deleted docs.
  Stream<List<WasteLoad>> watchLoads({int limit = 200}) {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  /// Active (in-flight) loads: draft, pendingWeighbridge, pendingCostReview.
  /// No limit — there are never many active loads at once.
  /// Used by [WasteHomeScreen] together with [watchRecentCompleted].
  Stream<List<WasteLoad>> watchActiveLoads() {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .where('status', whereIn: [
          WasteLoadStatus.draft.value,
          WasteLoadStatus.pendingWeighbridge.value,
          WasteLoadStatus.pendingCostReview.value,
          'in_progress', // future-proofing — set by web/Pulse, no mobile enum yet
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  /// The [limit] most-recently completed or cancelled loads.
  /// Used by [WasteHomeScreen] to show a "Recent" section below active loads.
  Stream<List<WasteLoad>> watchRecentCompleted({int limit = 10}) {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .where('status', whereIn: [
          WasteLoadStatus.completed.value,
          WasteLoadStatus.cancelled.value,
        ])
        .orderBy('completed_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  // ---------------------------------------------------------------------------
  // TWO-PHASE HANDOFF (manager schedules → guard collects → manager weighbridges)
  // ---------------------------------------------------------------------------

  /// Manager creates a shell load. No Cloud Function needed — no load number
  /// is assigned at scheduling time (number assigned when guard submits via [submitCollection]).
  /// [selectedStockIds] are stored on the load doc; stock items are NOT marked loaded
  /// here — that happens in [submitCollection] when the guard confirms them.
  /// Works offline: a local document ID is used and the write is queued in Hive.
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
    final payload = {
      'load_number': '',
      'contractor_id': contractorId,
      if (contractorName != null) 'contractor_name': contractorName,
      'main_waste_type': mainWasteType,
      'date_time': Timestamp.fromDate(scheduledFor),
      'createdAt': FieldValue.serverTimestamp(),
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
    };

    final online = await _checkOnline();
    if (online) {
      try {
        final doc = await _firestore
            .collection(Collections.wasteLoads)
            .add(payload)
            .timeout(_firestoreWriteTimeout);
        return doc.id;
      } catch (_) {
        // Fall through to offline queue.
      }
    }

    // Offline path: use a local placeholder ID so the caller can navigate to
    // the new load immediately; the real Firestore write replays on reconnect.
    final localId = 'offline_sched_${DateTime.now().millisecondsSinceEpoch}';
    final serialized = _serializeLoadDataForQueue(payload, DateTime.now());
    await _enqueueWasteOp(
      shouldQueue: true,
      collection: Collections.wasteLoads,
      operation: 'set',
      data: serialized,
      documentId: localId,
    );
    return localId;
  }

  /// Stream of all scheduled (not yet collected) loads, ordered by expected date ascending.
  /// Used by [WasteHomeScreen] "Incoming" section.
  Stream<List<WasteLoad>> watchScheduledLoads({int limit = 50}) {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .where('status', isEqualTo: WasteLoadStatus.scheduled.value)
        .orderBy('scheduled_for', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  /// Manager cancels a scheduled load before the guard begins collection.
  /// Throws [StateError] if the load is no longer in [scheduled] status (online only).
  /// When offline the cancel is queued; status will be applied on next sync.
  Future<void> cancelScheduledLoad(String loadId) async {
    final online = await _checkOnline();

    if (online) {
      final ref = _firestore.collection(Collections.wasteLoads).doc(loadId);
      try {
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final current = WasteLoadStatus.fromString(snap.data()?['status'] as String?);
          if (current != WasteLoadStatus.scheduled) {
            throw StateError(
                'Load is no longer scheduled — cannot cancel (current: ${current.value})');
          }
          tx.update(ref, {
            'status': WasteLoadStatus.cancelled.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
        return;
      } catch (e) {
        if (e is StateError) rethrow;
        // Network error — fall through to queue.
      }
    }

    await _enqueueWasteOp(
      shouldQueue: true,
      collection: Collections.wasteLoads,
      operation: 'update',
      data: {
        'status': WasteLoadStatus.cancelled.value,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      documentId: loadId,
    );
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

  Stream<WasteLoad?> watchLoad(String loadId) {
    return _firestore
        .collection(Collections.wasteLoads)
        .doc(loadId)
        .snapshots()
        .map((doc) => doc.exists ? WasteLoad.fromFirestore(doc) : null);
  }

  Future<({bool queuedOffline})> submitCollection({
    required String loadId,
    required String driverName,
    required String vehicleReg,
    required String collectedBy,
    String? collectedByName,
    required List<Map<String, dynamic>> itemsData,
    List<String> itemPhotoPaths = const [],
    List<String> loadPhotoPaths = const [],
    String? signatureLocalPath,
    String? contractorId,
    bool isQuantityOnly = false,
  }) async {
    final ref = _firestore.collection(Collections.wasteLoads).doc(loadId);
    final online = await _checkOnline();
    var queuedOffline = !online;
    final now = DateTime.now();

    // Quantity-only loads skip the weighbridge step entirely.
    final nextStatus = isQuantityOnly
        ? WasteLoadStatus.pendingCostReview
        : WasteLoadStatus.pendingWeighbridge;
    final timestampKey = isQuantityOnly ? 'pending_cost_review_at' : 'pending_weighbridge_at';

    final statusPayload = {
      'status': nextStatus.value,
      'driver_name': driverName,
      'vehicle_reg': vehicleReg,
      'collected_by': collectedBy,
      if (collectedByName != null) 'collected_by_name': collectedByName,
      timestampKey: now.toIso8601String(),
    };

    var statusAlreadyPending = false;
    if (online) {
      try {
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final current = WasteLoadStatus.fromString(snap.data()?['status'] as String?);
          if (current == WasteLoadStatus.pendingWeighbridge ||
              current == WasteLoadStatus.pendingCostReview) {
            statusAlreadyPending = true;
            return;
          }
          if (current != WasteLoadStatus.scheduled) {
            throw StateError('Load already started or completed (current: ${current.value})');
          }
          tx.update(ref, {
            ...statusPayload,
            timestampKey: FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }).timeout(_firestoreWriteTimeout);
      } on StateError {
        rethrow;
      } catch (_) {
        queuedOffline = true;
      }
    }

    await _enqueueWasteOp(
      shouldQueue: queuedOffline && !statusAlreadyPending,
      collection: Collections.wasteLoads,
      operation: 'update',
      data: statusPayload,
      documentId: loadId,
    );

    if (signatureLocalPath != null) {
      if (queuedOffline) {
        await queueOfflineWasteSignature(localPath: signatureLocalPath, loadId: loadId);
      } else {
        try {
          final sigUrl = await _uploadSignatureBytesDirect(
            await File(signatureLocalPath).readAsBytes(),
            loadId,
          ).timeout(_photoUploadTimeout);
          await ref.update({'driver_signature_url': sigUrl}).timeout(_firestoreWriteTimeout);
        } catch (_) {
          await queueOfflineWasteSignature(localPath: signatureLocalPath, loadId: loadId);
        }
      }
    }

    // Fetch rates once for the whole batch — avoids opening N Firestore listeners
    // (one per item) when each item would otherwise call lookupItemRate() in a loop.
    List<Map<String, dynamic>> ratesList = const [];
    if (contractorId != null) {
      try {
        ratesList = await watchRates()
            .first
            .timeout(const Duration(seconds: 6), onTimeout: () => []);
      } catch (_) {}
    }

    var totalPhotoCount = 0;
    for (final item in itemsData) {
      final itemRef = _firestore.collection(Collections.wasteItems).doc();
      final photoUrls = <String>[];

      for (final path in (item['localPhotoPaths'] as List<String>? ?? [])) {
        final url = await _resolveItemPhotoUrl(
          path: path,
          loadId: loadId,
          itemId: itemRef.id,
          forceQueue: queuedOffline,
        );
        if (url != null) photoUrls.add(url);
      }

      totalPhotoCount += photoUrls.length;

      // Prefill rate from the pre-fetched rates list (synchronous, no extra I/O).
      final itemSubtype = item['subtype'] as String? ?? '';
      final itemRate = contractorId != null && itemSubtype.isNotEmpty
          ? _rateFromList(ratesList, contractorId: contractorId, subtype: itemSubtype)
          : null;

      final itemData = Map<String, dynamic>.from(item)
        ..remove('localPhotoPaths')
        ..addAll({
          'load_id': loadId,
          'photos': photoUrls,
          'is_deleted': false,
          'createdAt': queuedOffline ? now.toIso8601String() : FieldValue.serverTimestamp(),
          if (itemRate != null) 'rate_per_kg': itemRate,
        });

      if (queuedOffline) {
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteItems,
          operation: 'set',
          data: itemData,
          documentId: itemRef.id,
        );
      } else {
        try {
          await itemRef.set({
            ...itemData,
            'createdAt': FieldValue.serverTimestamp(),
          }).timeout(_firestoreWriteTimeout);
        } catch (_) {
          queuedOffline = true;
          await _enqueueWasteOp(
            shouldQueue: true,
            collection: Collections.wasteItems,
            operation: 'set',
            data: itemData,
            documentId: itemRef.id,
          );
        }
      }
    }

    final loadPhotoUrls = <String>[];
    for (final path in loadPhotoPaths) {
      if (queuedOffline) {
        await queueOfflineWastePhoto(localPath: path, loadId: loadId);
        continue;
      }
      try {
        final url = await uploadWastePhoto(
          localPath: path,
          wasteRef: 'waste_loads/$loadId',
        ).timeout(_photoUploadTimeout);
        loadPhotoUrls.add(url);
      } catch (_) {
        await queueOfflineWastePhoto(localPath: path, loadId: loadId);
        queuedOffline = true;
      }
    }

    final photoCountPayload = {
      'photo_count': totalPhotoCount + loadPhotoUrls.length,
      if (loadPhotoUrls.isNotEmpty) 'load_photos': loadPhotoUrls,
    };
    if (queuedOffline) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteLoads,
        operation: 'update',
        data: photoCountPayload,
        documentId: loadId,
      );
    } else {
      try {
        await ref.update(photoCountPayload).timeout(_firestoreWriteTimeout);
      } catch (_) {
        queuedOffline = true;
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteLoads,
          operation: 'update',
          data: photoCountPayload,
          documentId: loadId,
        );
      }
    }

    return (queuedOffline: queuedOffline);
  }

  /// Guard/manager finishes loading on an on-the-spot [draft] load.
  /// Requires loaded-truck photos + driver signature.
  /// Quantity-only loads transition to [pendingCostReview]; all others to [pendingWeighbridge].
  Future<({bool queuedOffline})> finishLoading({
    required String loadId,
    required List<String> loadPhotoPaths,
    String? signatureLocalPath,
    required String finishedBy,
    String? finishedByName,
    bool isQuantityOnly = false,
  }) async {
    if (signatureLocalPath == null) {
      throw ArgumentError('Driver signature is required');
    }

    final ref = _firestore.collection(Collections.wasteLoads).doc(loadId);
    final online = await _checkOnline();
    var queuedOffline = !online;
    final now = DateTime.now();

    final nextStatus = isQuantityOnly
        ? WasteLoadStatus.pendingCostReview
        : WasteLoadStatus.pendingWeighbridge;
    final timestampKey = isQuantityOnly ? 'pending_cost_review_at' : 'pending_weighbridge_at';

    final statusPayload = {
      'status': nextStatus.value,
      timestampKey: now.toIso8601String(),
      'collected_by': finishedBy,
      if (finishedByName != null) 'collected_by_name': finishedByName,
    };

    var statusAlreadyPending = false;
    if (online) {
      try {
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final current = WasteLoadStatus.fromString(snap.data()?['status'] as String?);
          if (current == WasteLoadStatus.pendingWeighbridge ||
              current == WasteLoadStatus.pendingCostReview) {
            statusAlreadyPending = true;
            return;
          }
          if (current != WasteLoadStatus.draft) {
            throw StateError(
              'Load cannot be finished from status: ${current.value}',
            );
          }
          tx.update(ref, {
            ...statusPayload,
            timestampKey: FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }).timeout(_firestoreWriteTimeout);
      } on StateError {
        rethrow;
      } catch (_) {
        queuedOffline = true;
      }
    }

    await _enqueueWasteOp(
      shouldQueue: queuedOffline && !statusAlreadyPending,
      collection: Collections.wasteLoads,
      operation: 'update',
      data: statusPayload,
      documentId: loadId,
    );

    final loadPhotoUrls = <String>[];
    for (final path in loadPhotoPaths) {
      if (queuedOffline) {
        await queueOfflineWastePhoto(localPath: path, loadId: loadId);
        continue;
      }
      try {
        final url = await uploadWastePhoto(
          localPath: path,
          wasteRef: 'waste_loads/$loadId',
        ).timeout(_photoUploadTimeout);
        loadPhotoUrls.add(url);
      } catch (_) {
        await queueOfflineWastePhoto(localPath: path, loadId: loadId);
        queuedOffline = true;
      }
    }

    if (signatureLocalPath.isNotEmpty) {
      if (queuedOffline) {
        await queueOfflineWasteSignature(localPath: signatureLocalPath, loadId: loadId);
      } else {
        try {
          final sigUrl = await _uploadSignatureBytesDirect(
            await File(signatureLocalPath).readAsBytes(),
            loadId,
          ).timeout(_photoUploadTimeout);
          await ref.update({'driver_signature_url': sigUrl}).timeout(_firestoreWriteTimeout);
        } catch (_) {
          await queueOfflineWasteSignature(localPath: signatureLocalPath, loadId: loadId);
          queuedOffline = true;
        }
      }
    }

    if (loadPhotoUrls.isNotEmpty) {
      final photoPayload = {'load_photos': loadPhotoUrls};
      if (queuedOffline) {
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteLoads,
          operation: 'update',
          data: photoPayload,
          documentId: loadId,
        );
      } else {
        try {
          await ref.update(photoPayload).timeout(_firestoreWriteTimeout);
        } catch (_) {
          queuedOffline = true;
          await _enqueueWasteOp(
            shouldQueue: true,
            collection: Collections.wasteLoads,
            operation: 'update',
            data: photoPayload,
            documentId: loadId,
          );
        }
      }
    }

    return (queuedOffline: queuedOffline);
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

  /// Soft-deletes a waste_item atomically. Reverts the parent load's
  /// recorded_weight_kg and, if the item came from a stock record, reverts
  /// that stock item back to on_site — all in a single Firestore transaction.
  /// Throws [StateError] when offline; item deletion is a supervised action
  /// and partial offline state is worse than a clear "reconnect first" error.
  Future<void> deleteWasteItem(String itemId, {String? sourceStockId}) async {
    final online = await _checkOnline();
    if (!online) {
      throw StateError('Cannot delete items while offline — reconnect and try again');
    }

    final itemRef = _firestore.collection(Collections.wasteItems).doc(itemId);

    await _firestore.runTransaction((tx) async {
      // ── All reads first — Firestore transactions require reads before writes ──
      final itemSnap = await tx.get(itemRef);
      final data = itemSnap.data();
      if (data == null) return;

      final loadId = data['load_id'] as String?;
      final weightKg = (data['weight_kg'] as num?)?.toDouble() ?? 0.0;
      final stockId = sourceStockId ?? data['source_stock_id'] as String?;

      DocumentReference<Map<String, dynamic>>? loadRef;
      DocumentSnapshot<Map<String, dynamic>>? loadSnap;
      if (loadId != null && weightKg > 0) {
        loadRef = _firestore.collection(Collections.wasteLoads).doc(loadId);
        loadSnap = await tx.get(loadRef);
      }

      // ── All writes after reads ──

      // 1. Soft-delete the item
      tx.update(itemRef, {
        'is_deleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Decrement the parent load's recorded weight
      if (loadRef != null && loadSnap != null) {
        final currentRecorded =
            (loadSnap.data()?['recorded_weight_kg'] as num?)?.toDouble() ?? 0.0;
        final nextRecorded = (currentRecorded - weightKg).clamp(0.0, double.infinity);
        tx.update(loadRef, {'recorded_weight_kg': nextRecorded});
      }

      // 3. Revert the source stock item back to on_site
      if (stockId != null) {
        final stockRef = _firestore.collection(Collections.wasteStock).doc(stockId);
        tx.update(stockRef, {
          'status': WasteStockStatus.onSite.value,
          'load_id': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    });
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
  Future<({bool queuedOffline})> addItemToExistingLoad({
    required String loadId,
    required String subtype,
    required double weightKg,
    int? quantity,
    String? notes,
    required List<String> localPhotoPaths,
    String? sourceStockId,
    String? contractorId,
    bool isQuantityOnly = false,
  }) async {
    final online = await _checkOnline();
    var queuedOffline = !online;
    final itemRef = _firestore.collection(Collections.wasteItems).doc();
    final photoUrls = <String>[];
    final now = DateTime.now();

    // Prefill rate from waste_rates for per-item cost tracking.
    final rate = contractorId != null
        ? await lookupItemRate(contractorId: contractorId, subtype: subtype)
        : null;

    for (final path in localPhotoPaths) {
      final url = await _resolveItemPhotoUrl(
        path: path,
        loadId: loadId,
        itemId: itemRef.id,
        forceQueue: queuedOffline,
      );
      if (url != null) photoUrls.add(url);
    }

    final queueData = {
      'load_id': loadId,
      'subtype': subtype,
      'weight_kg': weightKg,
      if (quantity != null) 'quantity': quantity,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'photos': photoUrls,
      if (sourceStockId != null) 'source_stock_id': sourceStockId,
      'is_deleted': false,
      'is_quantity_only': isQuantityOnly,
      'createdAt': now.toIso8601String(),
      if (rate != null) 'rate_per_kg': rate,
    };

    final liveData = {
      ...queueData,
      'createdAt': FieldValue.serverTimestamp(),
    };

    var nextRecorded = weightKg;
    try {
      final loadSnap = await _firestore
          .collection(Collections.wasteLoads)
          .doc(loadId)
          .get(const GetOptions(source: Source.serverAndCache));
      final currentRecorded =
          (loadSnap.data()?['recorded_weight_kg'] as num?)?.toDouble() ?? 0.0;
      nextRecorded = currentRecorded + weightKg;
    } catch (_) {}

    final weightUpdate = {'recorded_weight_kg': nextRecorded};

    if (queuedOffline) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteItems,
        operation: 'set',
        data: queueData,
        documentId: itemRef.id,
      );
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteLoads,
        operation: 'update',
        data: weightUpdate,
        documentId: loadId,
      );
    } else {
      try {
        await itemRef.set(liveData).timeout(_firestoreWriteTimeout);
        await updateLoad(loadId, weightUpdate).timeout(_firestoreWriteTimeout);
      } catch (_) {
        queuedOffline = true;
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteItems,
          operation: 'set',
          data: queueData,
          documentId: itemRef.id,
        );
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteLoads,
          operation: 'update',
          data: weightUpdate,
          documentId: loadId,
        );
      }
    }

    return (queuedOffline: queuedOffline);
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
    bool forceQueue = false,
  }) async {
    if (_isRemotePhotoUrl(path)) return path;
    if (forceQueue) {
      await queueOfflineWastePhoto(
        localPath: path,
        loadId: loadId,
        itemId: itemId,
      );
      return null;
    }
    try {
      return await uploadWastePhoto(
        localPath: path,
        wasteRef: 'waste_items/$itemId',
      ).timeout(_photoUploadTimeout);
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

    // Delete the local compressed temp file after successful upload.
    try {
      await file.delete();
    } catch (_) {}

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

    final online = await _checkOnline();
    var queuedOffline = !online;
    final now = DateTime.now();
    final recordedTotal = itemsData.fold<double>(
      0.0,
      (acc, item) => acc + ((item['weight_kg'] as num?)?.toDouble() ?? 0.0),
    );

    String loadId;
    String loadNumber;

    if (online) {
      try {
        final cfResult = await createLoad({
          ...loadData,
          'recorded_weight_kg': recordedTotal,
        });
        loadId = cfResult['id'] as String;
        loadNumber = cfResult['load_number'] as String;
      } catch (_) {
        queuedOffline = true;
        loadId = _firestore.collection(Collections.wasteLoads).doc().id;
        loadNumber = 'OFFLINE-${now.millisecondsSinceEpoch}';
      }
    } else {
      loadId = _firestore.collection(Collections.wasteLoads).doc().id;
      loadNumber = 'OFFLINE-${now.millisecondsSinceEpoch}';
    }

    await logWasteUsage(
      'save_complete_waste_load',
      clockNo: actorClockNo,
      loadId: loadId,
    );

    final loadRef = 'waste_loads/$loadId';
    final loadPhotoUrls = <String>[];
    for (final localPath in loadLevelPhotoPaths) {
      if (queuedOffline) {
        await queueOfflineWastePhoto(localPath: localPath, loadId: loadId);
        continue;
      }
      try {
        final url = await uploadWastePhoto(
          localPath: localPath,
          wasteRef: loadRef,
        ).timeout(_photoUploadTimeout);
        loadPhotoUrls.add(url);
      } catch (_) {
        await queueOfflineWastePhoto(localPath: localPath, loadId: loadId);
      }
    }

    final serializedLoadData = _serializeLoadDataForQueue(loadData, now);
    final loadQueueData = {
      ...serializedLoadData,
      'load_number': loadNumber,
      'recorded_weight_kg': recordedTotal,
      'status': WasteLoadStatus.draft.value,
      'is_deleted': false,
      'load_photos': loadPhotoUrls,
      'photo_count': loadPhotoUrls.length,
      'createdAt': now.toIso8601String(),
      'date_time': now.toIso8601String(),
    };

    if (queuedOffline) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteLoads,
        operation: 'set',
        data: loadQueueData,
        documentId: loadId,
      );
    } else if (loadPhotoUrls.isNotEmpty) {
      // Load doc already exists from Cloud Function — only patch load-level photos.
      try {
        await updateLoad(loadId, {'load_photos': loadPhotoUrls})
            .timeout(_firestoreWriteTimeout);
      } catch (_) {
        queuedOffline = true;
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteLoads,
          operation: 'update',
          data: {'load_photos': loadPhotoUrls},
          documentId: loadId,
        );
      }
    }

    final batch = queuedOffline ? null : _firestore.batch();
    var totalPhotoCount = loadPhotoUrls.length;
    final pendingQueueItems = <({String id, Map<String, dynamic> data})>[];

    for (final rawItem in itemsData) {
      final itemRef = _firestore.collection(Collections.wasteItems).doc();
      final localPhotos = List<String>.from(rawItem['localPhotos'] ?? []);
      final itemBase = Map<String, dynamic>.from(rawItem)
        ..remove('localPhotos')
        ..addAll({
          'load_id': loadId,
          'is_deleted': false,
        });

      final photoUrls = <String>[];
      for (final localPath in localPhotos) {
        final url = await _resolveItemPhotoUrl(
          path: localPath,
          loadId: loadId,
          itemId: itemRef.id,
          forceQueue: queuedOffline,
        );
        if (url != null) photoUrls.add(url);
      }
      totalPhotoCount += photoUrls.length;

      final queueItemData = {
        ...itemBase,
        'photos': photoUrls,
        'createdAt': now.toIso8601String(),
      };

      if (queuedOffline) {
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteItems,
          operation: 'set',
          data: queueItemData,
          documentId: itemRef.id,
        );
      } else if (batch != null) {
        batch.set(itemRef, {
          ...itemBase,
          'photos': photoUrls,
          'createdAt': FieldValue.serverTimestamp(),
        });
        pendingQueueItems.add((id: itemRef.id, data: queueItemData));
      }
    }

    if (!queuedOffline && batch != null) {
      try {
        await batch.commit().timeout(_firestoreWriteTimeout);
        await updateLoad(loadId, {'photo_count': totalPhotoCount})
            .timeout(_firestoreWriteTimeout);
      } catch (_) {
        queuedOffline = true;
        for (final pending in pendingQueueItems) {
          await _enqueueWasteOp(
            shouldQueue: true,
            collection: Collections.wasteItems,
            operation: 'set',
            data: pending.data,
            documentId: pending.id,
          );
        }
        await _enqueueWasteOp(
          shouldQueue: true,
          collection: Collections.wasteLoads,
          operation: 'update',
          data: {'photo_count': totalPhotoCount},
          documentId: loadId,
        );
      }
    } else if (queuedOffline) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteLoads,
        operation: 'update',
        data: {'photo_count': totalPhotoCount},
        documentId: loadId,
      );
    }

    return {
      'id': loadId,
      'load_number': loadNumber,
      'success': true,
      'queuedOffline': queuedOffline,
    };
  }

  Map<String, dynamic> _serializeLoadDataForQueue(
    Map<String, dynamic> loadData,
    DateTime fallbackNow,
  ) {
    final serialized = <String, dynamic>{};
    for (final entry in loadData.entries) {
      final value = entry.value;
      if (value is DateTime) {
        serialized[entry.key] = value.toIso8601String();
      } else if (value is Timestamp) {
        serialized[entry.key] = value.toDate().toIso8601String();
      } else {
        serialized[entry.key] = value;
      }
    }
    if (!serialized.containsKey('date_time')) {
      serialized['date_time'] = fallbackNow.toIso8601String();
    }
    return serialized;
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

  /// Toggles the isQuantityOnly flag on an existing waste type.
  Future<void> setWasteTypeQuantityOnly(String typeId, bool isQuantityOnly) async {
    try {
      await _firestore.collection(Collections.wasteTypes).doc(typeId).update({
        'isQuantityOnly': isQuantityOnly,
      });
    } catch (e) {
      throw Exception('Failed to update waste type: $e');
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

  /// Synchronous rate lookup from a pre-fetched rates list.
  /// Used by [submitCollection] which fetches once for the whole batch.
  double? _rateFromList(
    List<Map<String, dynamic>> rates, {
    required String contractorId,
    required String subtype,
  }) {
    for (final r in rates) {
      if (r['contractor_id'] == contractorId && r['subtype'] == subtype) {
        return (r['cost_per_kg'] as num?)?.toDouble();
      }
    }
    for (final r in rates) {
      if (r['contractor_id'] == contractorId && r['subtype'] == 'default') {
        return (r['cost_per_kg'] as num?)?.toDouble();
      }
    }
    return null;
  }

  /// Looks up the rate per kg for a (contractorId, subtype) pair from waste_rates.
  /// Falls back to a 'default' subtype for the contractor if no exact match.
  /// Returns null if no rate exists — caller should leave the field blank.
  Future<double?> lookupItemRate({
    required String contractorId,
    required String subtype,
  }) async {
    try {
      final rates = await watchRates()
          .first
          .timeout(const Duration(seconds: 6), onTimeout: () => []);
      return _rateFromList(rates, contractorId: contractorId, subtype: subtype);
    } catch (_) {}
    return null;
  }

  /// Upserts a rate into waste_rates for (contractorId, subtype).
  /// If a rate already exists for this pair, updates it; otherwise creates a new doc.
  /// Called from the cost review screen when admin confirms or corrects an item rate.
  Future<void> upsertItemRate({
    required String contractorId,
    required String subtype,
    required double costPerKg,
    required String setBy,
  }) async {
    final existing = await _firestore
        .collection(Collections.wasteRates)
        .where('contractor_id', isEqualTo: contractorId)
        .where('subtype', isEqualTo: subtype)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({
        'cost_per_kg': costPerKg,
        'set_by': setBy,
        'set_at': FieldValue.serverTimestamp(),
      });
    } else {
      await setRate(
        contractorId: contractorId,
        subtype: subtype,
        costPerKg: costPerKg,
        setBy: setBy,
      );
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
        .where('is_deleted', isEqualTo: false)
        .where('status', isEqualTo: WasteLoadStatus.pendingWeighbridge.value)
        .orderBy('pending_weighbridge_at', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  /// Streams loads awaiting admin cost approval after weighbridge document entry.
  Stream<List<WasteLoad>> watchPendingCostReview() {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .where('status', isEqualTo: WasteLoadStatus.pendingCostReview.value)
        .orderBy('pending_cost_review_at', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  /// Suggests cost from [waste_rates] using item subtypes × weighbridge weight.
  Future<({double rate, double randValueExVat})?> suggestLoadCost({
    required String loadId,
    WasteLoad? load,
    required double weightKg,
  }) async {
    final resolvedLoad = load ?? await getLoad(loadId);
    if (resolvedLoad == null || weightKg <= 0) return null;

    final rates = await watchRates().first;
    double? costPerKgFor(String subtype) {
      for (final r in rates) {
        if (r['contractor_id'] == resolvedLoad.contractorId && r['subtype'] == subtype) {
          return (r['cost_per_kg'] as num?)?.toDouble();
        }
      }
      for (final r in rates) {
        if (r['contractor_id'] == resolvedLoad.contractorId && r['subtype'] == 'default') {
          return (r['cost_per_kg'] as num?)?.toDouble();
        }
      }
      return null;
    }

    final items = await watchItemsForLoad(loadId).first;
    if (items.isEmpty) {
      final rate = costPerKgFor(resolvedLoad.mainWasteType);
      if (rate == null || rate <= 0) return null;
      return (rate: rate, randValueExVat: weightKg * rate);
    }

    double totalWeight = 0;
    double weightedCost = 0;
    for (final item in items) {
      final w = item.weightKg;
      if (w <= 0) continue;
      final rate = costPerKgFor(item.subtype);
      if (rate == null || rate <= 0) continue;
      totalWeight += w;
      weightedCost += w * rate;
    }
    if (totalWeight <= 0 || weightedCost <= 0) return null;
    final avgRate = weightedCost / totalWeight;
    return (rate: avgRate, randValueExVat: weightKg * avgRate);
  }

  /// Admin confirms cost and marks load [completed].
  Future<void> approveCostReview({
    required String loadId,
    required double randValueExVat,
    double? rate,
    required String reviewedBy,
    double? calculatedCost,
    /// Per-item rate confirmations. For each entry: updates item doc with confirmed
    /// rate_per_kg and upserts the rate back into waste_rates (self-healing registry).
    List<({String itemId, String subtype, double ratePerKg, String contractorId})>
        itemRateUpdates = const [],
  }) async {
    // 1. Update each item's confirmed rate_per_kg in Firestore.
    for (final update in itemRateUpdates) {
      try {
        await _firestore
            .collection(Collections.wasteItems)
            .doc(update.itemId)
            .update({'rate_per_kg': update.ratePerKg});
        // Upsert back to waste_rates so future collections are pre-filled.
        await upsertItemRate(
          contractorId: update.contractorId,
          subtype: update.subtype,
          costPerKg: update.ratePerKg,
          setBy: reviewedBy,
        );
      } catch (_) {
        // Non-fatal: rate registry update fails gracefully.
      }
    }

    final updateData = {
      'status': WasteLoadStatus.completed.value,
      'rand_value_exvat': randValueExVat,
      if (rate != null) 'rate': rate,
      if (calculatedCost != null) 'calculated_cost': calculatedCost,
      'cost_reviewed_by': reviewedBy,
      'completed_by': reviewedBy,
      'completed_at': FieldValue.serverTimestamp(),
      'cost_reviewed_at': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    var queued = false;
    try {
      await updateLoad(loadId, updateData);
    } catch (_) {
      queued = true;
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteLoads,
        operation: 'update',
        data: {
          ...updateData.map((k, v) => MapEntry(k, v is FieldValue ? DateTime.now().toIso8601String() : v)),
        },
        documentId: loadId,
      );
    }
    if (queued) {
      unawaited(SyncService().processNow());
    }
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

  DateTime? _lastQueueProcess;

  /// Processes queued waste photos using the central SyncService queue + session queue.
  /// Debounced to 30 seconds so multiple screens calling this simultaneously don't
  /// each trigger a full queue drain.
  Future<int> processOfflineWasteQueue() async {
    final now = DateTime.now();
    if (_lastQueueProcess != null &&
        now.difference(_lastQueueProcess!) < const Duration(seconds: 30)) {
      return 0;
    }
    _lastQueueProcess = now;
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

    // Heal any loads that were written offline and still carry an OFFLINE-* placeholder number.
    // After the Hive queue replays their set/update, they exist in Firestore but need a real W-NNNN.
    try {
      final snap = await _firestore
          .collection(Collections.wasteLoads)
          .where('load_number', isGreaterThanOrEqualTo: 'OFFLINE-')
          .where('load_number', isLessThan: 'OFFLINE-￿')
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in snap.docs) {
        try {
          await _functions.httpsCallable('assignWasteLoadNumber').call({'loadId': doc.id});
        } catch (_) {
          // Non-fatal: will retry on next processOfflineWasteQueue call.
        }
      }
    } catch (_) {
      // Device still offline or quota error — ignore; next queue drain will retry.
    }

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

  WasteSettings? _cachedWasteSettings;

  Future<bool> isWasteTrackEnabledForCurrentUser(String? clockNo) async {
    final localEnabled = await getWasteMasterEnabled();
    if (!localEnabled) return false;
    try {
      _cachedWasteSettings ??= await getWasteSettings();
      return _cachedWasteSettings!.wasteEnabled;
    } catch (_) {
      return true; // Firestore unavailable; trust the local flag.
    }
  }

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

  Future<void> _queueStockPhotos({
    required String stockId,
    required List<String> localPhotoPaths,
  }) async {
    for (final path in localPhotoPaths) {
      await queueOfflineWastePhoto(
        localPath: path,
        loadId: stockId,
        itemId: stockId,
        targetCollection: Collections.wasteStock,
      );
    }
  }

  /// Creates a new on-site waste stock item.
  ///
  /// Offline-first: when there is no connectivity, photos and the stock doc are
  /// queued immediately (no Storage/Firestore blocking). When online, uploads
  /// use short timeouts so weak signal falls back to the queue instead of hanging.
  ///
  /// Returns the stock document ID and whether the save was queued for background sync.
  Future<({String id, bool queuedOffline})> addStockItem({
    required WasteStockItem item,
    required List<String> localPhotoPaths,
  }) async {
    final stockId = _firestore.collection(Collections.wasteStock).doc().id;
    final online = await _checkOnline();
    final photoUrls = <String>[];

    if (online) {
      for (final path in localPhotoPaths) {
        try {
          final url = await uploadWastePhoto(
            localPath: path,
            wasteRef: 'waste_stock/$stockId',
          ).timeout(_photoUploadTimeout);
          photoUrls.add(url);
        } catch (_) {
          await queueOfflineWastePhoto(
            localPath: path,
            loadId: stockId,
            itemId: stockId,
            targetCollection: Collections.wasteStock,
          );
        }
      }
    } else {
      await _queueStockPhotos(stockId: stockId, localPhotoPaths: localPhotoPaths);
    }

    final now = DateTime.now();
    final data = {
      ...item.toFirestore(),
      'photos': photoUrls,
      'is_deleted': false,
      'created_at': online ? FieldValue.serverTimestamp() : Timestamp.fromDate(now),
      'updated_at': online ? FieldValue.serverTimestamp() : Timestamp.fromDate(now),
    };

    final queueData = {
      ...item.toFirestore(),
      'photos': photoUrls,
      'is_deleted': false,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    var queuedOffline = !online;

    if (online) {
      try {
        await _firestore
            .collection(Collections.wasteStock)
            .doc(stockId)
            .set(data)
            .timeout(_firestoreWriteTimeout);
      } catch (_) {
        queuedOffline = true;
      }
    }

    if (queuedOffline) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteStock,
        operation: 'set',
        data: queueData,
        documentId: stockId,
      );
    }

    return (id: stockId, queuedOffline: queuedOffline);
  }

  /// Updates an on-site stock item (subtype, weight, notes, photos). Offline-first.
  Future<({bool queuedOffline})> updateStockItem({
    required String stockId,
    required String subtype,
    double? estimatedWeightKg,
    String? notes,
    required List<String> keptPhotoUrls,
    required List<String> newLocalPhotoPaths,
    List<String> removedPhotoUrls = const [],
  }) async {
    final online = await _checkOnline();
    final photoUrls = List<String>.from(keptPhotoUrls);

    if (online) {
      for (final path in newLocalPhotoPaths) {
        try {
          final url = await uploadWastePhoto(
            localPath: path,
            wasteRef: 'waste_stock/$stockId',
          ).timeout(_photoUploadTimeout);
          photoUrls.add(url);
        } catch (_) {
          await queueOfflineWastePhoto(
            localPath: path,
            loadId: stockId,
            itemId: stockId,
            targetCollection: Collections.wasteStock,
          );
        }
      }
    } else {
      await _queueStockPhotos(
        stockId: stockId,
        localPhotoPaths: newLocalPhotoPaths,
      );
    }

    for (final url in removedPhotoUrls) {
      if (_isRemotePhotoUrl(url)) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
    }

    final now = DateTime.now();
    final patch = {
      'subtype': subtype,
      'waste_type': subtype,
      'estimated_weight_kg': estimatedWeightKg,
      'notes': notes,
      'photos': photoUrls,
      'updated_at': online ? FieldValue.serverTimestamp() : Timestamp.fromDate(now),
    };

    final queueData = {
      'subtype': subtype,
      'waste_type': subtype,
      if (estimatedWeightKg != null) 'estimated_weight_kg': estimatedWeightKg,
      if (notes != null) 'notes': notes,
      'photos': photoUrls,
      'updated_at': now.toIso8601String(),
    };

    var queuedOffline = !online;
    if (online) {
      try {
        await _firestore
            .collection(Collections.wasteStock)
            .doc(stockId)
            .update(patch)
            .timeout(_firestoreWriteTimeout);
      } catch (_) {
        queuedOffline = true;
      }
    }

    if (queuedOffline) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteStock,
        operation: 'update',
        data: queueData,
        documentId: stockId,
      );
    }

    return (queuedOffline: queuedOffline);
  }

  /// Soft-deletes an on-site stock item (admin only in UI). Best-effort Storage cleanup.
  Future<void> softDeleteStockItem({
    required String stockId,
    List<String> photoUrls = const [],
  }) async {
    await _firestore.collection(Collections.wasteStock).doc(stockId).update({
      'is_deleted': true,
      'updated_at': FieldValue.serverTimestamp(),
    });
    for (final url in photoUrls) {
      if (_isRemotePhotoUrl(url)) {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }
    }
  }

  /// Streams all non-deleted on-site stock items for a given waste type, newest first.
  ///
  /// Uses a single-field Firestore filter (`waste_type`) and applies
  /// `is_deleted` / `status` / sort client-side so we don't depend on a
  /// 4-field composite index that may not be deployed yet.
  /// All on-site stock across every waste type (newest first).
  Stream<List<WasteStockItem>> watchAllStockOnSite() {
    return _firestore
        .collection(Collections.wasteStock)
        .snapshots()
        .map(_filterOnSiteStockDocs)
        .transform(
          StreamTransformer<List<WasteStockItem>, List<WasteStockItem>>.fromHandlers(
            handleData: (data, sink) => sink.add(data),
            handleError: (error, stackTrace, sink) {
              debugPrint('watchAllStockOnSite error: $error');
              sink.add(<WasteStockItem>[]);
            },
          ),
        );
  }

  Stream<List<WasteStockItem>> watchStockOnSite(String wasteType) {
    return _firestore
        .collection(Collections.wasteStock)
        .where('waste_type', isEqualTo: wasteType)
        .snapshots()
        .map(_filterOnSiteStockDocs)
        .transform(
          StreamTransformer<List<WasteStockItem>, List<WasteStockItem>>.fromHandlers(
            handleData: (data, sink) => sink.add(data),
            handleError: (error, stackTrace, sink) {
              debugPrint('watchStockOnSite error: $error');
              sink.add(<WasteStockItem>[]);
            },
          ),
        );
  }

  List<WasteStockItem> _filterOnSiteStockDocs(QuerySnapshot<Map<String, dynamic>> snap) {
    final items = <WasteStockItem>[];
    for (final doc in snap.docs) {
      try {
        final item = WasteStockItem.fromFirestore(doc);
        if (!item.isDeleted && item.status == WasteStockStatus.onSite) {
          items.add(item);
        }
      } catch (e, st) {
        debugPrint('Skipping waste_stock ${doc.id}: $e\n$st');
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Links stock items to a load by updating their status to loaded in a single batch.
  /// Persists pre-linked stock IDs on a load (guard sees them at collection).
  Future<void> updateLoadSelectedStock(
    String loadId,
    List<String> stockIds,
  ) async {
    await updateLoad(loadId, {'selected_stock_ids': stockIds});
  }

  /// Adds on-site stock items to a load as waste_items and marks stock loaded.
  Future<int> addStockItemsToLoad({
    required String loadId,
    required List<String> stockIds,
  }) async {
    if (stockIds.isEmpty) return 0;
    final stocks = await getStockItemsByIds(stockIds);
    final loadedIds = <String>[];
    for (final stock in stocks) {
      if (stock.id == null ||
          stock.isDeleted ||
          stock.status != WasteStockStatus.onSite) {
        continue;
      }
      final label = stock.subtype.isNotEmpty ? stock.subtype : stock.wasteType;
      if (label.isEmpty) continue;
      final weight = stock.estimatedWeightKg ?? 0;
      await addItemToExistingLoad(
        loadId: loadId,
        subtype: label,
        weightKg: weight > 0 ? weight : 0,
        notes: stock.notes,
        localPhotoPaths: stock.photos,
        sourceStockId: stock.id,
      );
      loadedIds.add(stock.id!);
    }
    if (loadedIds.isNotEmpty) {
      await markStockLoaded(loadedIds, loadId);
    }
    return loadedIds.length;
  }

  Future<void> markStockLoaded(List<String> stockIds, String loadId) async {
    if (stockIds.isEmpty) return;
    final online = await _checkOnline();
    final payload = {
      'status': WasteStockStatus.loaded.value,
      'load_id': loadId,
    };

    if (online) {
      try {
        final batch = _firestore.batch();
        for (final id in stockIds) {
          batch.update(_firestore.collection(Collections.wasteStock).doc(id), {
            ...payload,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit().timeout(_firestoreWriteTimeout);
        return;
      } catch (_) {
        // Fall through to queue below.
      }
    }

    for (final id in stockIds) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteStock,
        operation: 'update',
        data: payload,
        documentId: id,
      );
    }
  }

  /// Force-queues stock-loaded updates without a connectivity check.
  /// Use when the parent load submission was itself queued offline — both
  /// operations must replay together so stock is never marked loaded against
  /// a load that isn't in Firestore yet.
  Future<void> queueMarkStockLoaded(List<String> stockIds, String loadId) async {
    if (stockIds.isEmpty) return;
    final payload = {
      'status': WasteStockStatus.loaded.value,
      'load_id': loadId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    for (final id in stockIds) {
      await _enqueueWasteOp(
        shouldQueue: true,
        collection: Collections.wasteStock,
        operation: 'update',
        data: payload,
        documentId: id,
      );
    }
  }

  /// Returns the count and total estimated weight of all on-site stock.
  Future<({int count, double totalEstimatedKg})> getAllStockSummary() async {
    try {
      final snap = await _firestore.collection(Collections.wasteStock).get();
      final items = _filterOnSiteStockDocs(snap);
      final total = items.fold<double>(
        0.0, (acc, i) => acc + (i.estimatedWeightKg ?? 0.0));
      return (count: items.length, totalEstimatedKg: total);
    } catch (e) {
      debugPrint('getAllStockSummary error: $e');
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

