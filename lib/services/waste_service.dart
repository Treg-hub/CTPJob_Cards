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
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import 'connectivity_service.dart';
import '../utils/persona_audit.dart';
import 'sync_service.dart';
import '../models/contractor.dart';
import '../models/waste_settings.dart';
import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';
import '../utils/waste_collection_marker.dart';
import '../utils/waste_queue_batch.dart';
import '../utils/waste_stock_snapshot.dart';
import '../utils/waste_type_routing.dart';
import '../models/waste_stock_source.dart';
import 'copper_service.dart';

/// Service for all WasteTrack (Waste Management) operations.
///
/// Singleton. Offline media (photos/signatures) resilience is owned entirely
/// by the central SyncService Hive queue: files are copied into the app
/// documents dir (waste_media_queue/) at queue time so they survive cache
/// clears, and the queue processor deletes them after a successful upload.
class WasteService {
  void _guardWrite() => assertPersonaSubmitAllowed();

  static final WasteService _instance = WasteService._internal();
  factory WasteService() => _instance;
  WasteService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'africa-south1');

  /// Subdirectory of the app documents dir holding queued offline media.
  /// Files here are owned by the sync queue and deleted after upload.
  static const String mediaQueueDirName = SyncService.wasteMediaQueueDirName;

  static const Duration _photoUploadTimeout = Duration(seconds: 12);
  static const Duration _firestoreWriteTimeout = Duration(seconds: 8);
  static const Duration _cloudFunctionTimeout = Duration(seconds: 15);

  /// Namespace for deterministic waste_item doc ids on queue-first submits.
  static const String _wasteItemIdNamespace = 'a3f2c8e1-4b5d-6e7f-8901-23456789abcd';

  Future<bool> _checkOnline() =>
      ConnectivityService().isOnline().catchError((_) => false);

  /// Guard-facing saves always queue locally first; this drains the Hive queue
  /// in the background without blocking the floor workflow.
  void _triggerBackgroundWasteSync() {
    unawaited(SyncService().processNow());
  }

  String _stableWasteItemDocId(String loadId, String submitRef, int index) {
    return const Uuid().v5(
      _wasteItemIdNamespace,
      'waste_item:$loadId:$submitRef:$index',
    );
  }

  String _stablePhotoQueueDocId({
    required String loadId,
    required String submitRef,
    required int index,
    String? itemId,
  }) {
    final scope = itemId ?? 'load';
    return '${loadId}_${scope}_${submitRef.substring(0, 8)}_$index';
  }

  bool _statusPastScheduled(WasteLoadStatus status) {
    return status == WasteLoadStatus.pendingWeighbridge ||
        status == WasteLoadStatus.pendingCostReview ||
        status == WasteLoadStatus.completed;
  }

  Future<WasteLoadStatus?> _readLoadStatus(String loadId) async {
    try {
      final snap = await _firestore
          .collection(Collections.wasteLoads)
          .doc(loadId)
          .get(const GetOptions(source: Source.cache));
      if (snap.exists) {
        return WasteLoadStatus.fromString(snap.data()?['status'] as String?);
      }
    } catch (_) {}
    try {
      final snap = await _firestore
          .collection(Collections.wasteLoads)
          .doc(loadId)
          .get()
          .timeout(const Duration(seconds: 2));
      if (!snap.exists) return null;
      return WasteLoadStatus.fromString(snap.data()?['status'] as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> _markLocalCollectionSubmitted(String loadId, String submitRef) async {
    await WasteCollectionMarker.setMarker(loadId, submitRef);
  }

  Future<void> clearLocalCollectionSubmitMarker(String loadId) async {
    await WasteCollectionMarker.clearMarker(loadId);
  }

  /// Idempotent guard: returns true when this load was already submitted (server
  /// or local marker with pending queue work) so we must not enqueue duplicates.
  Future<bool> _isCollectionAlreadySubmitted(String loadId) async {
    if (await WasteCollectionMarker.hasMarker(loadId)) {
      if (SyncService().hasQueuedWasteOpsForLoad(loadId)) {
        return true;
      }
      await WasteCollectionMarker.clearMarker(loadId);
    }
    final status = await _readLoadStatus(loadId);
    if (status == null) return false;
    return _statusPastScheduled(status);
  }

  Future<void> _assertLoadSchedulableForCollection(String loadId) async {
    final status = await _readLoadStatus(loadId);
    if (status == null) return;
    if (_statusPastScheduled(status)) return;
    if (status != WasteLoadStatus.scheduled) {
      throw StateError(
        'Load already started or completed (current: ${status.value})',
      );
    }
  }

  /// Only enqueue when offline or a direct Firestore write failed.
  Future<void> _enqueueWasteOp({
    required bool shouldQueue,
    required String collection,
    required String operation,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    _guardWrite();
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
    _guardWrite();
    try {
      final callable = _functions.httpsCallable('createWasteLoad');
      final result = await callable
          .call(initialData)
          .timeout(_cloudFunctionTimeout);
      return Map<String, dynamic>.from(result.data);
    } on TimeoutException {
      // Ambiguous: the request may have committed server-side even though we
      // never saw the response. Rethrown as-is (not wrapped) so callers like
      // [_createLoadWithRetry] can distinguish this from a definite failure.
      rethrow;
    } catch (e) {
      throw Exception('Failed to create waste load via Cloud Function: $e');
    }
  }

  /// Calls [createLoad] with retry-safe idempotency via a stable `client_ref`.
  ///
  /// A timeout is ambiguous — the request may have committed server-side even
  /// though the client never saw the response — so this retries exactly once,
  /// reusing the SAME client_ref. createWasteLoad's server-side dedup check
  /// then returns the already-created doc instead of minting a duplicate if
  /// the first attempt actually landed. Only falls back to a local
  /// OFFLINE-* placeholder (queued for later reconciliation) once the retry
  /// also fails, or on a definite (non-timeout) failure.
  Future<({String id, String loadNumber, bool queuedOffline})> _createLoadWithRetry(
    Map<String, dynamic> loadData,
  ) async {
    final clientRef = const Uuid().v4();
    final payload = {...loadData, 'client_ref': clientRef};
    try {
      final result = await createLoad(payload);
      return (id: result['id'] as String, loadNumber: result['load_number'] as String, queuedOffline: false);
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('createLoad timed out (ambiguous outcome) — retrying with client_ref $clientRef: $e');
      }
      try {
        final retryResult = await createLoad(payload);
        return (
          id: retryResult['id'] as String,
          loadNumber: retryResult['load_number'] as String,
          queuedOffline: false,
        );
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('createLoad retry after timeout failed for client_ref $clientRef: $e2');
        }
        final now = DateTime.now();
        return (
          id: _firestore.collection(Collections.wasteLoads).doc().id,
          loadNumber: 'OFFLINE-${now.millisecondsSinceEpoch}',
          queuedOffline: true,
        );
      }
    } catch (_) {
      final now = DateTime.now();
      return (
        id: _firestore.collection(Collections.wasteLoads).doc().id,
        loadNumber: 'OFFLINE-${now.millisecondsSinceEpoch}',
        queuedOffline: true,
      );
    }
  }

  /// Issues W-NNNN for loads with empty or OFFLINE-* provisional numbers.
  Future<String?> assignLoadNumberIfNeeded(String loadId) async {
    try {
      final result = await _functions
          .httpsCallable('assignWasteLoadNumber')
          .call({'loadId': loadId})
          .timeout(_cloudFunctionTimeout);
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['load_number'] as String?;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('assignLoadNumberIfNeeded failed for $loadId: $e');
      }
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD - LOADS
  // ---------------------------------------------------------------------------

  Future<({bool queuedOffline})> updateLoad(
      String loadId, Map<String, dynamic> data) async {
    _guardWrite();
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
    _guardWrite();
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
    _guardWrite();
    await _firestore.collection(Collections.wasteLoads).doc(loadId).update({
      'status': 'completed',
      if (driverSignatureUrl != null) 'driver_signature_url': driverSignatureUrl,
      'completed_by': completedBy,
      'completed_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> softDeleteLoad(String loadId, String deletedBy) async {
    _guardWrite();
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

  /// How far back the mobile home lists reach. Older loads stay visible in
  /// Reports and Pulse — the home screen is a recent-work view (and the
  /// server-side cutoff saves Firestore reads).
  static const Duration homeListWindow = Duration(days: 14);

  Timestamp get _homeWindowCutoff =>
      Timestamp.fromDate(DateTime.now().subtract(homeListWindow));

  /// Active (in-flight) loads from the last [homeListWindow]: draft,
  /// pendingWeighbridge, pendingCostReview. Older stragglers remain visible
  /// in Pulse. Used by [WasteHomeScreen] together with [watchRecentCompleted].
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
        .where('createdAt', isGreaterThanOrEqualTo: _homeWindowCutoff)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => WasteLoad.fromFirestore(d)).toList());
  }

  /// The [limit] most-recently completed or cancelled loads within
  /// [homeListWindow]. Used by [WasteHomeScreen] "Recent" section.
  Stream<List<WasteLoad>> watchRecentCompleted({int limit = 10}) {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .where('status', whereIn: [
          WasteLoadStatus.completed.value,
          WasteLoadStatus.cancelled.value,
        ])
        .where('completed_at', isGreaterThanOrEqualTo: _homeWindowCutoff)
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
  /// Schedules a load (manager-facing). Mirrors [saveCompleteWasteLoad]'s
  /// online/offline numbering pattern — calls the createWasteLoad CF
  /// immediately (via [_createLoadWithRetry], client_ref-protected) so a
  /// scheduled load gets a real W-NNNN (or a reconciled OFFLINE-* placeholder)
  /// up front, instead of deferring numbering to the guard's eventual
  /// submitCollection call. That deferred approach left a real gap: if the
  /// guard's submission ever happened offline, the load could be stuck with
  /// no number at all, since the sync queue only reconciles numbers for
  /// 'set'/'create' ops, not the 'update' op submitCollection queues.
  Future<String> createScheduledLoad({
    required String contractorId,
    String? contractorName,
    required String mainWasteType,
    required DateTime scheduledFor,
    required String scheduledBy,
    required String scheduledByName,
    String? scheduledNotes,
    String? paperDocumentRef,
    List<String> selectedStockIds = const [],
    List<String> selectedWasteTypes = const [],
  }) async {
    _guardWrite();
    final scheduleFields = {
      'contractor_id': contractorId,
      if (contractorName != null) 'contractor_name': contractorName,
      'main_waste_type': mainWasteType,
      if (selectedWasteTypes.isNotEmpty) 'selected_waste_types': selectedWasteTypes,
      'scheduled_for': Timestamp.fromDate(scheduledFor),
      'scheduled_by': scheduledBy,
      'scheduled_by_name': scheduledByName,
      if (scheduledByName.isNotEmpty) 'security_name': scheduledByName,
      if (scheduledNotes != null && scheduledNotes.isNotEmpty)
        'scheduled_notes': scheduledNotes,
      if (paperDocumentRef != null && paperDocumentRef.isNotEmpty)
        'paper_document_ref': paperDocumentRef,
      'status': WasteLoadStatus.scheduled.value,
      'driver_name': '',
      'vehicle_reg': '',
      'created_by': scheduledBy,
      if (selectedStockIds.isNotEmpty) 'selected_stock_ids': selectedStockIds,
    };

    final online = await _checkOnline();
    if (online) {
      final cfOutcome = await _createLoadWithRetry({
        ...scheduleFields,
        // Top-level sibling key (not part of the spread loadData) — the CF
        // destructures this separately to set date_time = scheduledFor
        // instead of its own now-based default.
        'date': scheduledFor.toIso8601String(),
      });
      if (!cfOutcome.queuedOffline) return cfOutcome.id;
      // Fall through to the offline branch below using the placeholder the
      // helper already minted, so both paths share one queueing code path.
      return _queueScheduledLoadOffline(
        scheduleFields,
        loadId: cfOutcome.id,
        loadNumber: cfOutcome.loadNumber,
        scheduledFor: scheduledFor,
      );
    }

    final now = DateTime.now();
    return _queueScheduledLoadOffline(
      scheduleFields,
      loadId: _firestore.collection(Collections.wasteLoads).doc().id,
      loadNumber: 'OFFLINE-${now.millisecondsSinceEpoch}',
      scheduledFor: scheduledFor,
    );
  }

  /// Queues a scheduled-load doc for offline sync with an OFFLINE-* placeholder
  /// number, reconciled by [sync_service]'s existing 'set'/'create' →
  /// assignWasteLoadNumber path once connectivity returns.
  Future<String> _queueScheduledLoadOffline(
    Map<String, dynamic> scheduleFields, {
    required String loadId,
    required String loadNumber,
    required DateTime scheduledFor,
  }) async {
    final now = DateTime.now();
    final payload = {
      ...scheduleFields,
      'load_number': loadNumber,
      'date_time': scheduledFor.toIso8601String(),
      'createdAt': now.toIso8601String(),
      'load_photos': const <String>[],
      'is_deleted': false,
      'recorded_weight_kg': 0.0,
    };
    final serialized = _serializeLoadDataForQueue(payload, now);
    await _enqueueWasteOp(
      shouldQueue: true,
      collection: Collections.wasteLoads,
      operation: 'set',
      data: serialized,
      documentId: loadId,
    );
    return loadId;
  }

  /// Stream of scheduled (not yet collected) loads, ordered by expected date
  /// ascending. One range on `scheduled_for` covers both future-scheduled
  /// loads and recently-past ones still inside [homeListWindow] (docs missing
  /// `scheduled_for` were already excluded by the orderBy).
  /// Used by [WasteHomeScreen] "Incoming" section.
  Stream<List<WasteLoad>> watchScheduledLoads({int limit = 50}) {
    return _firestore
        .collection(Collections.wasteLoads)
        .where('is_deleted', isEqualTo: false)
        .where('status', isEqualTo: WasteLoadStatus.scheduled.value)
        .where('scheduled_for', isGreaterThanOrEqualTo: _homeWindowCutoff)
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
    _guardWrite();
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

  /// Records an admin's use of the "show all contractor types" override at
  /// Begin Collection — i.e. adding item type(s) outside the manager's
  /// originally-scheduled [WasteLoad.selectedWasteTypes]. Mirrors the
  /// waste_audit shape already used by CTP Pulse (action/triggered_by/
  /// created_at) so the entry is queryable alongside weighbridge-deviation
  /// and soft-delete audit records. Best-effort — failures are swallowed so
  /// a logging hiccup never blocks the guard's actual collection submit.
  Future<void> logWasteTypeOverrideAudit({
    required String loadId,
    required String loadNumber,
    required String adminClockNo,
    String? adminName,
    required List<String> addedTypes,
  }) async {
    if (addedTypes.isEmpty) return;
    try {
      await _firestore.collection(Collections.wasteAudit).add({
        'load_id': loadId,
        'load_number': loadNumber,
        'action': 'type_restriction_override',
        'added_types': addedTypes,
        'triggered_by': adminClockNo,
        if (adminName != null) 'triggered_by_name': adminName,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('logWasteTypeOverrideAudit failed for $loadId: $e');
    }
  }

  /// Recent `media_lost` audit entries — queued photos/signatures whose local
  /// file was permanently lost before sync (written by SyncService at replay
  /// time). Surfaced in WasteQueuedScreen so the loss is visible instead of
  /// silent. No orderBy: avoids a composite index; volume is tiny, so results
  /// are sorted client-side. Best-effort — returns [] on any error.
  Future<List<Map<String, dynamic>>> getRecentLostMediaAudit(
      {int limit = 20}) async {
    try {
      final snap = await _firestore
          .collection(Collections.wasteAudit)
          .where('action', isEqualTo: 'media_lost')
          .limit(50)
          .get()
          .timeout(_firestoreWriteTimeout);
      final entries = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'media_type': data['media_type'],
          'load_id': data['load_id'],
          'item_id': data['item_id'],
          'queued_at': (data['queued_at'] as Timestamp?)?.toDate(),
          'created_at': (data['created_at'] as Timestamp?)?.toDate(),
        };
      }).toList()
        ..sort((a, b) {
          final ad = a['created_at'] as DateTime?;
          final bd = b['created_at'] as DateTime?;
          if (ad == null || bd == null) return ad == null ? 1 : -1;
          return bd.compareTo(ad);
        });
      return entries.take(limit).toList();
    } catch (_) {
      return [];
    }
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

  Future<({bool queuedOffline, int queuedOps})> submitCollection({
    required String loadId,
    required String driverName,
    required String vehicleReg,
    String? trailerReg,
    required String collectedBy,
    String? collectedByName,
    required List<Map<String, dynamic>> itemsData,
    List<String> itemPhotoPaths = const [],
    List<String> loadPhotoPaths = const [],
    String? signatureLocalPath,
    String? contractorId,
    bool isQuantityOnly = false,
    String? securityName,
    String? timeIn,
    String? timeOut,
    String? paperDocumentRef,
    String? collectionSubmitRef,
  }) async {
    _guardWrite();
    final submitRef = collectionSubmitRef ?? const Uuid().v4();
    final now = DateTime.now();

    if (await _isCollectionAlreadySubmitted(loadId)) {
      _triggerBackgroundWasteSync();
      return (
        queuedOffline: true,
        queuedOps: SyncService().getQueuedWasteOperationCount(),
      );
    }

    await _assertLoadSchedulableForCollection(loadId);

    final skipWeighbridge = isQuantityOnly ||
        itemsAllQuantityOnly(
          itemsData.map((i) => i['is_quantity_only'] == true),
        );
    final recordedWeightKg = sumRecordedWeightKg(itemsData);

    final nextStatus = skipWeighbridge
        ? WasteLoadStatus.pendingCostReview
        : WasteLoadStatus.pendingWeighbridge;
    final timestampKey =
        skipWeighbridge ? 'pending_cost_review_at' : 'pending_weighbridge_at';

    var totalPhotoCount = loadPhotoPaths.length;
    for (final item in itemsData) {
      totalPhotoCount +=
          (item['localPhotoPaths'] as List?)?.length ?? 0;
    }

    final statusPayload = {
      'status': nextStatus.value,
      'driver_name': driverName,
      'vehicle_reg': vehicleReg,
      if (trailerReg != null && trailerReg.isNotEmpty) 'trailer_reg': trailerReg,
      'collected_by': collectedBy,
      if (collectedByName != null) 'collected_by_name': collectedByName,
      if (securityName != null && securityName.isNotEmpty) 'security_name': securityName,
      if (timeIn != null && timeIn.isNotEmpty) 'time_in': timeIn,
      if (timeOut != null && timeOut.isNotEmpty) 'time_out': timeOut,
      if (paperDocumentRef != null && paperDocumentRef.isNotEmpty)
        'paper_document_ref': paperDocumentRef,
      'recorded_weight_kg': recordedWeightKg,
      'collection_submit_ref': submitRef,
      'photo_count': totalPhotoCount,
      timestampKey: now.toIso8601String(),
    };

    final plan = WasteQueueBatchPlan();
    plan.addFirestore(
      collection: Collections.wasteLoads,
      operation: 'update',
      data: statusPayload,
      documentId: loadId,
    );
    _addLoadPhotosToPlan(
      plan: plan,
      loadId: loadId,
      submitRef: submitRef,
      photoPaths: loadPhotoPaths,
    );
    if (signatureLocalPath != null) {
      plan.addSignature(
        localPath: signatureLocalPath,
        loadId: loadId,
        queueDocumentId: '${loadId}_sig_${submitRef.substring(0, 8)}',
      );
    }
    for (var i = 0; i < itemsData.length; i++) {
      _addWasteItemStepsToPlan(
        plan: plan,
        loadId: loadId,
        submitRef: submitRef,
        itemIndex: i,
        rawItem: itemsData[i],
        now: now,
        extraItemFields: {
          'is_no_site_weight': itemsData[i]['is_no_site_weight'] == true,
          'collection_submit_ref': submitRef,
        },
      );
    }
    await _flushWasteQueuePlan(plan);

    await _markLocalCollectionSubmitted(loadId, submitRef);
    _triggerBackgroundWasteSync();

    return (
      queuedOffline: true,
      queuedOps: SyncService().getQueuedWasteOperationCount(),
    );
  }

  /// Guard/manager finishes loading on an on-the-spot [draft] load.
  /// Loaded-truck photos + driver signature are required only when [photosRequired]/
  /// [signatureRequired] (from waste_settings) say so — settings-driven, matching
  /// the equivalent gating in [submitCollection] for the scheduled-load path.
  /// Quantity-only loads transition to [pendingCostReview]; all others to [pendingWeighbridge].
  Future<({bool queuedOffline, int queuedOps})> finishLoading({
    required String loadId,
    required List<String> loadPhotoPaths,
    String? signatureLocalPath,
    bool signatureRequired = false,
    bool photosRequired = false,
    required String finishedBy,
    String? finishedByName,
    bool isQuantityOnly = false,
    String? finishSubmitRef,
  }) async {
    _guardWrite();
    if (signatureRequired && signatureLocalPath == null) {
      throw ArgumentError('Driver signature is required');
    }
    if (photosRequired && loadPhotoPaths.isEmpty) {
      throw ArgumentError('At least one loaded-truck photo is required');
    }

    final submitRef = finishSubmitRef ?? const Uuid().v4();
    final now = DateTime.now();

    if (await _isCollectionAlreadySubmitted(loadId)) {
      _triggerBackgroundWasteSync();
      return (
        queuedOffline: true,
        queuedOps: SyncService().getQueuedWasteOperationCount(),
      );
    }

    final status = await _readLoadStatus(loadId);
    if (status != null &&
        status != WasteLoadStatus.draft &&
        !_statusPastScheduled(status)) {
      throw StateError('Load cannot be finished from status: ${status.value}');
    }

    final nextStatus = isQuantityOnly
        ? WasteLoadStatus.pendingCostReview
        : WasteLoadStatus.pendingWeighbridge;
    final timestampKey =
        isQuantityOnly ? 'pending_cost_review_at' : 'pending_weighbridge_at';

    final statusPayload = {
      'status': nextStatus.value,
      timestampKey: now.toIso8601String(),
      'collected_by': finishedBy,
      if (finishedByName != null) 'collected_by_name': finishedByName,
      'finish_submit_ref': submitRef,
      if (loadPhotoPaths.isNotEmpty) 'photo_count': loadPhotoPaths.length,
    };

    final plan = WasteQueueBatchPlan();
    plan.addFirestore(
      collection: Collections.wasteLoads,
      operation: 'update',
      data: statusPayload,
      documentId: loadId,
    );
    _addLoadPhotosToPlan(
      plan: plan,
      loadId: loadId,
      submitRef: submitRef,
      photoPaths: loadPhotoPaths,
    );
    if (signatureLocalPath != null && signatureLocalPath.isNotEmpty) {
      plan.addSignature(
        localPath: signatureLocalPath,
        loadId: loadId,
        queueDocumentId: '${loadId}_sig_${submitRef.substring(0, 8)}',
      );
    }
    await _flushWasteQueuePlan(plan);

    await _markLocalCollectionSubmitted(loadId, submitRef);
    _triggerBackgroundWasteSync();

    return (
      queuedOffline: true,
      queuedOps: SyncService().getQueuedWasteOperationCount(),
    );
  }

  // ---------------------------------------------------------------------------
  // CRUD - ITEMS
  // ---------------------------------------------------------------------------

  Future<String> addItem(WasteItem item) async {
    _guardWrite();
    final doc = await _firestore.collection(Collections.wasteItems).add(item.toFirestore());
    return doc.id;
  }

  Future<void> updateItem(String itemId, Map<String, dynamic> data) async {
    _guardWrite();
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

  /// Resolves eligible on-site stock for create-load queuing. UI snapshots are
  /// authoritative offline; Firestore fills any IDs missing from snapshots.
  Future<List<Map<String, dynamic>>> _resolveEligibleStockForSave({
    required List<String> selectedStockIds,
    required List<Map<String, dynamic>> snapshots,
  }) async {
    if (selectedStockIds.isEmpty) return const [];
    final eligible = WasteStockSnapshot.eligibleForQueue(
      selectedStockIds,
      snapshots,
    );
    final foundIds = eligible
        .map((s) => s['id'] as String?)
        .whereType<String>()
        .toSet();
    final missingIds =
        selectedStockIds.where((id) => !foundIds.contains(id)).toList();
    if (missingIds.isEmpty) return eligible;

    final fetched = await getStockItemsByIds(missingIds);
    final merged = List<Map<String, dynamic>>.from(eligible);
    for (final stock in fetched) {
      if (stock.id == null ||
          stock.isDeleted ||
          stock.status != WasteStockStatus.onSite) {
        continue;
      }
      merged.add(WasteStockSnapshot.fromItem(stock));
    }
    return merged;
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
          .get(const GetOptions(source: Source.serverAndCache));
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
    _guardWrite();
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
      final countsTowardRecorded = data['is_quantity_only'] != true &&
          data['is_no_site_weight'] != true &&
          weightKg > 0;
      final stockId = sourceStockId ?? data['source_stock_id'] as String?;

      DocumentReference<Map<String, dynamic>>? loadRef;
      DocumentSnapshot<Map<String, dynamic>>? loadSnap;
      if (loadId != null && countsTowardRecorded) {
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
  /// Queue-first — never blocks on connectivity or live photo upload.
  Future<({bool queuedOffline, int queuedOps})> addItemToExistingLoad({
    required String loadId,
    required String subtype,
    required double weightKg,
    int? quantity,
    String? notes,
    required List<String> localPhotoPaths,
    String? sourceStockId,
    bool isQuantityOnly = false,
    bool isNoSiteWeight = false,
  }) async {
    _guardWrite();
    final itemId = _firestore.collection(Collections.wasteItems).doc().id;
    final now = DateTime.now();
    final countsTowardRecorded =
        !isQuantityOnly && !isNoSiteWeight && weightKg > 0;
    final split = _splitPhotoPaths(localPhotoPaths);

    final plan = WasteQueueBatchPlan();
    plan.addFirestore(
      collection: Collections.wasteItems,
      operation: 'set',
      data: {
        'load_id': loadId,
        'subtype': subtype,
        'weight_kg': weightKg,
        if (quantity != null) 'quantity': quantity,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'photos': split.remote,
        if (sourceStockId != null) 'source_stock_id': sourceStockId,
        'is_deleted': false,
        'is_quantity_only': isQuantityOnly,
        'is_no_site_weight': isNoSiteWeight,
        'createdAt': now.toIso8601String(),
      },
      documentId: itemId,
    );
    for (var p = 0; p < split.local.length; p++) {
      plan.addPhoto(
        localPath: split.local[p],
        loadId: loadId,
        itemId: itemId,
        queueDocumentId: '${loadId}_${itemId}_add_$p',
      );
    }

    if (countsTowardRecorded) {
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
      plan.addFirestore(
        collection: Collections.wasteLoads,
        operation: 'update',
        data: {'recorded_weight_kg': nextRecorded},
        documentId: loadId,
      );
    }

    await _flushWasteQueuePlan(plan);
    _triggerBackgroundWasteSync();
    return (
      queuedOffline: true,
      queuedOps: SyncService().getQueuedWasteOperationCount(),
    );
  }

  // ---------------------------------------------------------------------------
  // PHOTO HANDLING (reused & adapted from Job Cards patterns)
  // ---------------------------------------------------------------------------

  bool _isRemotePhotoUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  ({List<String> remote, List<String> local}) _splitPhotoPaths(
    List<String> paths,
  ) {
    final remote = <String>[];
    final local = <String>[];
    for (final path in paths) {
      if (_isRemotePhotoUrl(path)) {
        remote.add(path);
      } else {
        local.add(path);
      }
    }
    return (remote: remote, local: local);
  }

  void _addLoadPhotosToPlan({
    required WasteQueueBatchPlan plan,
    required String loadId,
    required String submitRef,
    required List<String> photoPaths,
  }) {
    for (var i = 0; i < photoPaths.length; i++) {
      plan.addPhoto(
        localPath: photoPaths[i],
        loadId: loadId,
        queueDocumentId: _stablePhotoQueueDocId(
          loadId: loadId,
          submitRef: submitRef,
          index: i,
        ),
      );
    }
  }

  void _addWasteItemStepsToPlan({
    required WasteQueueBatchPlan plan,
    required String loadId,
    required String submitRef,
    required int itemIndex,
    required Map<String, dynamic> rawItem,
    required DateTime now,
    Map<String, dynamic> extraItemFields = const {},
  }) {
    final itemId = _stableWasteItemDocId(loadId, submitRef, itemIndex);
    final photoPaths = List<String>.from(
      rawItem['localPhotoPaths'] as List? ??
          rawItem['localPhotos'] as List? ??
          const [],
    );
    final split = _splitPhotoPaths(photoPaths);
    final itemData = Map<String, dynamic>.from(rawItem)
      ..remove('localPhotoPaths')
      ..remove('localPhotos')
      ..addAll({
        'load_id': loadId,
        'is_deleted': false,
        'photos': split.remote,
        'createdAt': now.toIso8601String(),
        ...extraItemFields,
      });

    plan.addFirestore(
      collection: Collections.wasteItems,
      operation: 'set',
      data: itemData,
      documentId: itemId,
    );

    for (var p = 0; p < split.local.length; p++) {
      plan.addPhoto(
        localPath: split.local[p],
        loadId: loadId,
        itemId: itemId,
        queueDocumentId: _stablePhotoQueueDocId(
          loadId: loadId,
          submitRef: submitRef,
          index: p,
          itemId: itemId,
        ),
      );
    }
  }

  Future<void> _flushWasteQueuePlan(WasteQueueBatchPlan plan) async {
    if (plan.isEmpty) return;
    _guardWrite();
    await plan.flush();
  }

  /// Persists captured signature bytes into the durable media queue dir.
  Future<String> persistSignatureBytes(Uint8List bytes) =>
      _persistSignatureBytesForQueue(bytes);

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
    final path = compressedFile?.path;
    if (path == null) return null;
    try {
      return await SyncService.persistWasteMediaForQueue(path);
    } catch (_) {
      return path;
    }
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
    _guardWrite();
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
      final localPath = await _persistSignatureBytesForQueue(signatureBytes);
      await queueOfflineWasteSignature(localPath: localPath, loadId: loadId);
      rethrow;
    }
  }

  // Internal direct upload (no queuing) - used by public API and offline processor.
  Future<String> _uploadSignatureBytesDirect(Uint8List bytes, String loadId) async {
    _guardWrite();
    final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
    final storagePath = 'waste_loads/$loadId/signature/$fileName';
    final ref = _storage.ref().child(storagePath);
    final snapshot = await ref.putData(bytes);
    return await snapshot.ref.getDownloadURL();
  }

  /// Writes signature bytes to a file in the persistent media queue dir
  /// (falls back to the system temp dir if that fails — the queue-time copy
  /// in [queueOfflineWasteSignature] then persists it).
  Future<String> _persistSignatureBytesForQueue(Uint8List bytes) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    String dirPath;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final queueDir = Directory(
          '${docsDir.path}${Platform.pathSeparator}$mediaQueueDirName');
      if (!queueDir.existsSync()) {
        queueDir.createSync(recursive: true);
      }
      dirPath = queueDir.path;
    } catch (_) {
      dirPath = Directory.systemTemp.path;
    }
    // Timestamp + uuid: two signatures captured in the same millisecond must
    // not share a path (the queue dedupes by localPath).
    final path =
        '$dirPath${Platform.pathSeparator}waste_sig_${ts}_${const Uuid().v4()}.png';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Queues a signature (by persisted file path) for later upload via the
  /// central SyncService Hive queue (single owner — no session queue). The
  /// file is copied into the persistent media dir first.
  Future<void> queueOfflineWasteSignature({
    required String localPath,
    required String loadId,
    String? queueDocumentId,
  }) async {
    _guardWrite();
    final persistentPath = await _persistMediaForQueue(localPath);
    await SyncService().addToQueue(
      collection: 'waste_signatures',
      operation: 'upload',
      data: {
        'localPath': persistentPath,
        'loadId': loadId,
      },
      documentId:
          queueDocumentId ?? '${loadId}_sig_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// New offline-aware helper: persist bytes to temp + queue (central + session). Used by detail screen when network unavailable.
  Future<void> queueOfflineWasteSignatureBytes({
    required Uint8List signatureBytes,
    required String loadId,
  }) async {
    final localPath = await _persistSignatureBytesForQueue(signatureBytes);
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
    List<String> selectedStockIds = const [],         // on-site stock → waste_items on create
    List<Map<String, dynamic>> selectedStockSnapshots = const [],
    String? actorClockNo,                             // for enhanced pilot flag check + usage logging
    String? createSubmitRef,
  }) async {
    _guardWrite();
    final allowed = await isWasteTrackEnabledForCurrentUser(actorClockNo);
    if (!allowed) {
      throw Exception('WasteTrack is currently disabled by feature flag or your account is not in the active pilot group');
    }

    final submitRef = createSubmitRef ?? const Uuid().v4();
    final now = DateTime.now();

    final eligibleStock = await _resolveEligibleStockForSave(
      selectedStockIds: selectedStockIds,
      snapshots: selectedStockSnapshots,
    );

    var recordedTotal = itemsData.fold<double>(
      0.0,
      (acc, item) => acc + ((item['weight_kg'] as num?)?.toDouble() ?? 0.0),
    );
    for (final stock in eligibleStock) {
      final w = WasteStockSnapshot.weightKg(stock);
      if (w > 0) recordedTotal += w;
    }

    var totalPhotoCount = loadLevelPhotoPaths.length;
    for (final rawItem in itemsData) {
      final paths = List<String>.from(rawItem['localPhotos'] ?? []);
      totalPhotoCount += paths.length;
    }
    for (final stock in eligibleStock) {
      totalPhotoCount += WasteStockSnapshot.photos(stock).length;
    }

    final loadId = _firestore.collection(Collections.wasteLoads).doc().id;
    final loadNumber = 'OFFLINE-${now.millisecondsSinceEpoch}';

    unawaited(logWasteUsage(
      'save_complete_waste_load',
      clockNo: actorClockNo,
      loadId: loadId,
    ));

    final serializedLoadData = _serializeLoadDataForQueue(loadData, now);
    final loadQueueData = {
      ...serializedLoadData,
      'load_number': loadNumber,
      'recorded_weight_kg': recordedTotal,
      'status': WasteLoadStatus.draft.value,
      'is_deleted': false,
      'client_ref': submitRef,
      'create_submit_ref': submitRef,
      'load_photos': <String>[],
      'photo_count': totalPhotoCount,
      if (selectedStockIds.isNotEmpty) 'selected_stock_ids': selectedStockIds,
      'createdAt': now.toIso8601String(),
      'date_time': now.toIso8601String(),
    };

    final plan = WasteQueueBatchPlan();
    _addLoadPhotosToPlan(
      plan: plan,
      loadId: loadId,
      submitRef: submitRef,
      photoPaths: loadLevelPhotoPaths,
    );
    plan.addFirestore(
      collection: Collections.wasteLoads,
      operation: 'set',
      data: loadQueueData,
      documentId: loadId,
    );

    for (var i = 0; i < itemsData.length; i++) {
      _addWasteItemStepsToPlan(
        plan: plan,
        loadId: loadId,
        submitRef: submitRef,
        itemIndex: i,
        rawItem: itemsData[i],
        now: now,
        extraItemFields: {'create_submit_ref': submitRef},
      );
    }

    final stockLoadedIds = <String>[];
    var stockItemIndex = itemsData.length;
    for (final stock in eligibleStock) {
      final label = WasteStockSnapshot.label(stock);
      if (label.isEmpty) continue;
      final stockId = stock['id'] as String?;
      if (stockId == null || stockId.isEmpty) continue;
      final itemId =
          _stableWasteItemDocId(loadId, submitRef, stockItemIndex++);
      final split = _splitPhotoPaths(WasteStockSnapshot.photos(stock));
      final weight = WasteStockSnapshot.weightKg(stock);
      final qty = WasteStockSnapshot.quantity(stock);
      final notes = stock['notes'] as String?;

      plan.addFirestore(
        collection: Collections.wasteItems,
        operation: 'set',
        data: {
          'load_id': loadId,
          'subtype': label,
          'weight_kg': weight > 0 ? weight : 0,
          if (qty > 0) 'quantity': qty,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          'photos': split.remote,
          'source_stock_id': stockId,
          'is_deleted': false,
          'create_submit_ref': submitRef,
          'createdAt': now.toIso8601String(),
        },
        documentId: itemId,
      );
      for (var p = 0; p < split.local.length; p++) {
        plan.addPhoto(
          localPath: split.local[p],
          loadId: loadId,
          itemId: itemId,
          queueDocumentId: _stablePhotoQueueDocId(
            loadId: loadId,
            submitRef: submitRef,
            index: p,
            itemId: itemId,
          ),
        );
      }
      stockLoadedIds.add(stockId);
    }

    if (stockLoadedIds.isNotEmpty) {
      final stockPayload = {
        'status': WasteStockStatus.loaded.value,
        'load_id': loadId,
        'updated_at': now.toIso8601String(),
      };
      for (final id in stockLoadedIds) {
        plan.addFirestore(
          collection: Collections.wasteStock,
          operation: 'update',
          data: stockPayload,
          documentId: id,
        );
      }
    }

    await _flushWasteQueuePlan(plan);

    _triggerBackgroundWasteSync();

    return {
      'id': loadId,
      'load_number': loadNumber,
      'success': true,
      'queuedOffline': true,
      'queuedOps': SyncService().getQueuedWasteOperationCount(),
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
    _guardWrite();
    try {
      final doc = await _firestore.collection(Collections.wasteTypes).add(type.toFirestore());
      return doc.id;
    } catch (e) {
      throw Exception('Failed to create waste type: $e');
    }
  }

  /// Toggles the isQuantityOnly flag on an existing waste type.
  Future<void> setWasteTypeQuantityOnly(String typeId, bool isQuantityOnly) async {
    _guardWrite();
    try {
      await _firestore.collection(Collections.wasteTypes).doc(typeId).update({
        'isQuantityOnly': isQuantityOnly,
        if (isQuantityOnly) 'noSiteWeight': false, // mutually exclusive
      });
    } catch (e) {
      throw Exception('Failed to update waste type: $e');
    }
  }

  /// Toggles the noSiteWeight flag on an existing waste type.
  Future<void> setWasteTypeNoSiteWeight(String typeId, bool noSiteWeight) async {
    _guardWrite();
    try {
      await _firestore.collection(Collections.wasteTypes).doc(typeId).update({
        'noSiteWeight': noSiteWeight,
        if (noSiteWeight) 'isQuantityOnly': false, // mutually exclusive
      });
    } catch (e) {
      throw Exception('Failed to update waste type: $e');
    }
  }

  /// Adds a subtype to an existing waste type (arrayUnion for safety).
  Future<void> addSubtypeToType(String typeId, String newSubtype) async {
    _guardWrite();
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

    double calculatedTotal = 0;
    double totalWeight = 0;
    for (final item in items) {
      final rate = costPerKgFor(item.subtype);
      if (rate == null || rate <= 0) continue;
      if (item.isQuantityOnly) {
        calculatedTotal += (item.quantity ?? 0) * rate;
        continue;
      }
      final w = item.weightKg;
      if (w <= 0) continue;
      totalWeight += w;
      calculatedTotal += w * rate;
    }
    if (calculatedTotal > 0) {
      final avgRate = totalWeight > 0 ? calculatedTotal / totalWeight : calculatedTotal / weightKg;
      return (rate: avgRate, randValueExVat: calculatedTotal);
    }
    if (totalWeight <= 0) return null;
    final avgRate = calculatedTotal / totalWeight;
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

    await _recordCopperSalesIfNeeded(loadId: loadId, reviewedBy: reviewedBy);
  }

  /// When a Copper Waste load completes, record commercial sale in copper_transactions.
  Future<void> _recordCopperSalesIfNeeded({
    required String loadId,
    required String reviewedBy,
  }) async {
    try {
      final loadSnap =
          await _firestore.collection(Collections.wasteLoads).doc(loadId).get();
      if (!loadSnap.exists) return;
      final load = WasteLoad.fromFirestore(loadSnap);
      if (load.mainWasteType != WasteStockTypes.copperWaste) return;

      final itemsSnap = await _firestore
          .collection(Collections.wasteItems)
          .where('load_id', isEqualTo: loadId)
          .get();
      final copperService = CopperService();
      for (final doc in itemsSnap.docs) {
        final data = doc.data();
        if (data['is_deleted'] == true) continue;
        final subtype = (data['subtype'] as String?) ?? '';
        if (subtype != WasteStockTypes.copperRods &&
            subtype != WasteStockTypes.copperNuggets) {
          continue;
        }
        final weight = (data['weight_kg'] as num?)?.toDouble() ?? 0.0;
        final rate = (data['rate_per_kg'] as num?)?.toDouble() ?? 0.0;
        if (weight <= 0 || rate <= 0) continue;
        await copperService.recordSaleFromWasteLoad(
          loadId: loadId,
          loadNumber: load.loadNumber,
          subtype: subtype,
          amountKg: weight,
          rPerKg: rate,
          userId: reviewedBy,
        );
      }
    } catch (_) {
      // Non-fatal: waste load completion must not fail on copper audit write.
    }
  }

  // ---------------------------------------------------------------------------
  // OFFLINE INTEGRATION (PR2-3) — hooks into existing SyncService/Hive
  // ---------------------------------------------------------------------------

  /// Copies a queued media file into the persistent app documents dir
  /// (waste_media_queue/) so it survives OS cache clears while waiting for
  /// sync. Delegates to [SyncService.persistWasteMediaForQueue].
  Future<String> _persistMediaForQueue(String localPath) =>
      SyncService.persistWasteMediaForQueue(localPath);

  /// Queues a waste photo for later upload when offline via the central
  /// SyncService Hive queue (single owner — no session queue). The file is
  /// first copied into the persistent media dir so a cache clear before the
  /// next sync cannot lose it.
  /// [targetCollection] overrides the default routing in the queue processor;
  /// used by stock photos so it patches waste_stock instead of waste_items.
  Future<void> queueOfflineWastePhoto({
    required String localPath,
    required String loadId,
    String? itemId,
    String? targetCollection,
    String? queueDocumentId,
  }) async {
    final persistentPath = await _persistMediaForQueue(localPath);
    await SyncService().addToQueue(
      collection: 'waste_photos',
      operation: 'upload',
      data: {
        'localPath': persistentPath,
        'loadId': loadId,
        'itemId': itemId,
        if (targetCollection != null) 'targetCollection': targetCollection,
      },
      documentId: queueDocumentId ??
          '${loadId}_${itemId ?? 'load'}_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  DateTime? _lastQueueProcess;

  /// Drains the central SyncService Hive queue (the single owner of all
  /// queued waste writes, photos, and signatures) and heals OFFLINE-* load
  /// numbers. Debounced to 30 seconds so multiple screens calling this
  /// simultaneously don't each trigger a full queue drain.
  Future<int> processOfflineWasteQueue() async {
    final now = DateTime.now();
    if (_lastQueueProcess != null &&
        now.difference(_lastQueueProcess!) < const Duration(seconds: 30)) {
      return 0;
    }
    _lastQueueProcess = now;
    const uploaded = 0;
    // Central Hive queue (the single production path for offline resilience)
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
    _guardWrite();
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

  Future<WasteSettings> getWasteSettings({Source? source}) async {
    final snap = await _firestore
        .collection(Collections.wasteSettings)
        .doc('config')
        .get(source != null ? GetOptions(source: source) : const GetOptions());
    if (!snap.exists) return WasteSettings.defaults;
    return WasteSettings.fromFirestore(snap);
  }

  Stream<WasteSettings> watchSettings() {
    return _firestore
        .collection(Collections.wasteSettings)
        .doc('config')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return WasteSettings.defaults;
      return WasteSettings.fromFirestore(snap);
    });
  }

  Future<void> saveWasteSettings(WasteSettings settings) async {
    _guardWrite();
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
      await queueMarkStockLoaded(loadedIds, loadId);
      _triggerBackgroundWasteSync();
    }
    return loadedIds.length;
  }

  Future<void> markStockLoaded(List<String> stockIds, String loadId) async {
    _guardWrite();
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
        await CopperService().clearActiveBatchIfNoOnSiteThresholdStock();
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
    await CopperService().clearActiveBatchIfNoOnSiteThresholdStock();
  }

  /// Force-queues stock-loaded updates without a connectivity check.
  /// Use when the parent load submission was itself queued offline — both
  /// operations must replay together so stock is never marked loaded against
  /// a load that isn't in Firestore yet.
  Future<void> queueMarkStockLoaded(List<String> stockIds, String loadId) async {
    _guardWrite();
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

  /// Splits [takeQty] units off an IBC pool/split stock doc (`poolStockId`)
  /// into a new on-site doc, decrementing the source by the same amount and
  /// carrying that many of its `linked_ibc_numbers` across. Used when a
  /// manager/guard takes only part of the on-site IBC quantity onto a load.
  ///
  /// Always creates a new doc — even when [takeQty] equals the full current
  /// quantity — rather than repurposing the pool doc itself. This keeps the
  /// pool doc's identity stable as the ongoing accumulator (it can sit at
  /// quantity 0 and simply increment again on the next ink IBC consume)
  /// instead of needing to clear/repoint `waste_stock_pool_pointers/ibc_bins`
  /// every time a load takes everything currently on site.
  ///
  /// The returned id is the new doc — callers should link/select that id for
  /// the load instead of [poolStockId].
  Future<String> splitPoolStock({
    required String poolStockId,
    required int takeQty,
  }) async {
    _guardWrite();
    if (takeQty <= 0) {
      throw ArgumentError('takeQty must be positive');
    }
    // Pool stock is shared read-modify-write state — transactions can't run
    // offline and must not be queued blind, so fail fast with a clear message.
    if (!await _checkOnline()) {
      throw StateError(
          'No connection — pool stock changes need to be online. Reconnect and try again.');
    }
    final poolRef = _firestore.collection(Collections.wasteStock).doc(poolStockId);
    final newRef = _firestore.collection(Collections.wasteStock).doc();

    try {
      await _runSplitPoolStockTxn(poolRef, newRef, takeQty)
          .timeout(_cloudFunctionTimeout);
    } on TimeoutException {
      // The timeout does not cancel the transaction — it may still commit.
      throw StateError(
          'Connection too slow — the change may not have saved. Check the stock list before retrying.');
    }

    return newRef.id;
  }

  Future<void> _runSplitPoolStockTxn(
    DocumentReference<Map<String, dynamic>> poolRef,
    DocumentReference<Map<String, dynamic>> newRef,
    int takeQty,
  ) async {
    await _firestore.runTransaction((tx) async {
      final poolSnap = await tx.get(poolRef);
      if (!poolSnap.exists) {
        throw StateError('Stock item not found.');
      }
      final data = poolSnap.data()!;
      final currentQty = (data['quantity'] as num?)?.toInt() ?? 0;
      if (takeQty > currentQty) {
        throw StateError('Only $currentQty on site — cannot take $takeQty.');
      }
      final linked = (data['linked_ibc_numbers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      final taken = linked.take(takeQty).toList();
      final remaining = linked.skip(takeQty).toList();

      tx.update(poolRef, {
        'quantity': FieldValue.increment(-takeQty),
        if (linked.isNotEmpty) 'linked_ibc_numbers': remaining,
        'updated_at': FieldValue.serverTimestamp(),
      });

      tx.set(newRef, {
        'waste_type': data['waste_type'],
        'subtype': data['subtype'],
        'photos': <String>[],
        'quantity': takeQty,
        if (taken.isNotEmpty) 'linked_ibc_numbers': taken,
        'source': data['source'],
        if (data['source_ref'] != null) 'source_ref': data['source_ref'],
        'visibility': data['visibility'],
        'auto_created': true,
        'status': WasteStockStatus.onSite.value,
        'created_by': data['created_by'],
        'created_by_name': data['created_by_name'],
        'is_deleted': false,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'notes': 'Split from on-site pool for load selection',
      });
    });
  }

  /// Removes [count] damaged/scrapped units from a stock item discovered at
  /// Begin Collection — distinct from a plain "remove from load" (which
  /// returns the item to on-site stock untouched). Damaged units are
  /// permanently excluded: if [count] covers the item's full remaining
  /// quantity the doc is disposed entirely; otherwise its quantity is
  /// decremented and the flagged IBC numbers are dropped from
  /// `linked_ibc_numbers`. Either way, the specified `ink_ibcs` docs are
  /// flagged with the damage reason, and a best-effort `waste_audit` entry is
  /// written (mirrors [logWasteTypeOverrideAudit]'s shape).
  Future<void> removeDamagedIbcUnits({
    required String stockId,
    required int count,
    required List<String> ibcNumbersToFlag,
    required String reason,
    required String actorClockNo,
    String? actorName,
    String? loadId,
    String? loadNumber,
  }) async {
    _guardWrite();
    if (count <= 0) {
      throw ArgumentError('count must be positive');
    }
    // Same online-only rule as splitPoolStock: shared pool state, no blind queueing.
    if (!await _checkOnline()) {
      throw StateError(
          'No connection — pool stock changes need to be online. Reconnect and try again.');
    }
    final stockRef = _firestore.collection(Collections.wasteStock).doc(stockId);

    try {
      await _runRemoveDamagedIbcUnitsTxn(
        stockRef: stockRef,
        count: count,
        ibcNumbersToFlag: ibcNumbersToFlag,
        reason: reason,
        actorClockNo: actorClockNo,
      ).timeout(_cloudFunctionTimeout);
    } on TimeoutException {
      // The timeout does not cancel the transaction — it may still commit.
      throw StateError(
          'Connection too slow — the change may not have saved. Check the stock list before retrying.');
    }

    try {
      await _firestore.collection(Collections.wasteAudit).add({
        if (loadId != null) 'load_id': loadId,
        if (loadNumber != null) 'load_number': loadNumber,
        'stock_id': stockId,
        'ibc_numbers': ibcNumbersToFlag,
        'count': count,
        'reason': reason,
        'action': 'ibc_damaged_removed',
        'triggered_by': actorClockNo,
        if (actorName != null) 'triggered_by_name': actorName,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('removeDamagedIbcUnits audit log failed for $stockId: $e');
    }
  }

  Future<void> _runRemoveDamagedIbcUnitsTxn({
    required DocumentReference<Map<String, dynamic>> stockRef,
    required int count,
    required List<String> ibcNumbersToFlag,
    required String reason,
    required String actorClockNo,
  }) async {
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(stockRef);
      if (!snap.exists) {
        throw StateError('Stock item not found.');
      }
      final data = snap.data()!;
      final currentQty = (data['quantity'] as num?)?.toInt() ?? 1;
      final now = FieldValue.serverTimestamp();

      if (count >= currentQty) {
        tx.update(stockRef, {
          'status': WasteStockStatus.disposed.value,
          'damaged': true,
          'is_deleted': true,
          'updated_at': now,
          'notes': 'Removed at Begin Collection — damaged/scrapped: $reason',
        });
      } else {
        final linked = (data['linked_ibc_numbers'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        final remaining = linked.where((n) => !ibcNumbersToFlag.contains(n)).toList();
        tx.update(stockRef, {
          'quantity': FieldValue.increment(-count),
          if (linked.isNotEmpty) 'linked_ibc_numbers': remaining,
          'updated_at': now,
        });
      }

      for (final ibcNumber in ibcNumbersToFlag) {
        tx.set(
          _firestore.collection(Collections.inkIbcs).doc(ibcNumber),
          {
            'damage_flag': true,
            'damage_reason': reason,
            'damage_recorded_at': now,
            'damage_recorded_by': actorClockNo,
          },
          SetOptions(merge: true),
        );
      }
    });
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

