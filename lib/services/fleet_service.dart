import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/fleet_asset.dart';
import '../models/fleet_cost_line.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_comment.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

/// All Fleet Maintenance Firestore and Storage operations.
/// Follows the WasteService singleton pattern.
class FleetService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'africa-south1');

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------

  Future<FleetSettings> getSettings() async {
    final snap =
        await _db.collection(Collections.fleetSettings).doc('config').get();
    if (!snap.exists) return FleetSettings.defaults;
    return FleetSettings.fromFirestore(snap);
  }

  Stream<FleetSettings> watchSettings() {
    return _db
        .collection(Collections.fleetSettings)
        .doc('config')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return FleetSettings.defaults;
      return FleetSettings.fromFirestore(snap);
    });
  }

  Future<void> saveSettings(FleetSettings settings) async {
    await _db
        .collection(Collections.fleetSettings)
        .doc('config')
        .set(settings.toFirestore(), SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // TYPES (asset types + work types)
  // ---------------------------------------------------------------------------

  Stream<List<FleetType>> watchTypes({required String kind}) {
    // Single-field filter only (auto-indexed). Active filtering + sort done
    // in memory so no composite index is required.
    return _db
        .collection(Collections.fleetTypes)
        .where('kind', isEqualTo: kind)
        .snapshots()
        .map((s) {
          final all = s.docs.map(FleetType.fromFirestore).toList();
          final active = all.where((t) => t.active).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          return active;
        });
  }

  /// Saves a new issue-part label if no active type with the same label exists.
  Future<void> ensureIssuePartType(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final existing = await _db
        .collection(Collections.fleetTypes)
        .where('kind', isEqualTo: 'issue_part')
        .get();
    final normalised = trimmed.toLowerCase();
    final duplicate = existing.docs.any((doc) {
      final data = doc.data();
      final existingLabel = (data['label'] as String? ?? '').trim().toLowerCase();
      return existingLabel == normalised;
    });
    if (duplicate) return;
    await saveType(FleetType(kind: 'issue_part', label: trimmed, sortOrder: 99));
  }

  Future<void> saveType(FleetType type) async {
    if (type.id == null) {
      await _db.collection(Collections.fleetTypes).add(type.toFirestore());
    } else {
      await _db
          .collection(Collections.fleetTypes)
          .doc(type.id)
          .set(type.toFirestore(), SetOptions(merge: true));
    }
  }

  Future<void> deactivateType(String typeId) async {
    await _db
        .collection(Collections.fleetTypes)
        .doc(typeId)
        .update({'active': false});
  }

  // ---------------------------------------------------------------------------
  // ASSETS
  // ---------------------------------------------------------------------------

  Stream<List<FleetAsset>> watchAssets({bool activeOnly = true}) {
    // Sort in memory to avoid composite index requirement.
    return _db
        .collection(Collections.fleetAssets)
        .snapshots()
        .map((s) {
          final all = s.docs.map(FleetAsset.fromFirestore).toList();
          final filtered = activeOnly ? all.where((a) => a.active).toList() : all;
          filtered.sort((a, b) => a.name.compareTo(b.name));
          return filtered;
        });
  }

  Future<FleetAsset?> getAsset(String id) async {
    final snap =
        await _db.collection(Collections.fleetAssets).doc(id).get();
    if (!snap.exists) return null;
    return FleetAsset.fromFirestore(snap);
  }

  Future<void> saveAsset(FleetAsset asset) async {
    if (asset.id == null) {
      await _db.collection(Collections.fleetAssets).add(asset.toFirestore());
    } else {
      await _db
          .collection(Collections.fleetAssets)
          .doc(asset.id)
          .set(asset.toFirestore(), SetOptions(merge: true));
    }
  }

  // ---------------------------------------------------------------------------
  // ISSUES
  // ---------------------------------------------------------------------------

  Future<String> createIssue(FleetIssue issue) async {
    final ref = await _db
        .collection(Collections.fleetIssues)
        .add(issue.toFirestore());
    return ref.id;
  }

  Future<void> updateIssuePhotos(String issueId, List<String> photos) async {
    await _db
        .collection(Collections.fleetIssues)
        .doc(issueId)
        .update({'photos': photos});
  }

  Stream<List<FleetIssue>> watchIssues({
    String? status,
    String? assetId,
    String? reportedByClockNo,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q =
        _db.collection(Collections.fleetIssues);
    if (status != null) q = q.where('status', isEqualTo: status);
    if (assetId != null) q = q.where('asset_id', isEqualTo: assetId);
    if (reportedByClockNo != null) {
      q = q.where('reported_by_clock_no', isEqualTo: reportedByClockNo);
    }
    return q
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(FleetIssue.fromFirestore).toList());
  }

  Stream<List<FleetIssue>> watchOpenIssues({int limit = 20}) {
    return _db
        .collection(Collections.fleetIssues)
        .where('status', whereIn: ['open', 'acknowledged'])
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) {
          final issues = s.docs.map(FleetIssue.fromFirestore).toList();
          // Sort by severity priority (OOS first, then high, medium, low)
          issues.sort(
              (a, b) => a.severity.sortOrder.compareTo(b.severity.sortOrder));
          return issues;
        });
  }

  Future<FleetIssue?> getIssue(String id) async {
    final snap =
        await _db.collection(Collections.fleetIssues).doc(id).get();
    if (!snap.exists) return null;
    return FleetIssue.fromFirestore(snap);
  }

  Stream<FleetIssue?> watchIssue(String id) {
    return _db
        .collection(Collections.fleetIssues)
        .doc(id)
        .snapshots()
        .map((snap) =>
            snap.exists ? FleetIssue.fromFirestore(snap) : null);
  }

  Future<void> acknowledgeIssue(String issueId, String clockNo, String name) async {
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'acknowledged',
      'acknowledged_by_clock_no': clockNo,
      'acknowledged_by_name': name,
      'acknowledged_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveIssueWithNote(
      String issueId, String note, String clockNo, String name) async {
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'resolved',
      'resolution_type': 'note',
      'resolution_note': note,
      'resolved_by_clock_no': clockNo,
      'resolved_by_name': name,
      'resolved_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveIssueWithWorkRecord(
      String issueId, String workRecordId, String clockNo, String name) async {
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'resolved',
      'resolution_type': 'work_record',
      'linked_work_record_id': workRecordId,
      'resolved_by_clock_no': clockNo,
      'resolved_by_name': name,
      'resolved_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelIssue(
      String issueId, String clockNo, String name, {String? reason}) async {
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'cancelled',
      'cancelled_by_clock_no': clockNo,
      'cancelled_by_name': name,
      if (reason != null) 'cancel_reason': reason,
      'cancelled_at': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // WORK RECORDS
  // ---------------------------------------------------------------------------

  /// Creates a new work record via Cloud Function (gets FM-YYYYMMDD-NNN number).
  Future<Map<String, dynamic>> createWorkRecord(
      Map<String, dynamic> data) async {
    try {
      final callable = _functions.httpsCallable('createFleetWorkRecord');
      final result = await callable.call(data);
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      throw Exception('Failed to create fleet work record: $e');
    }
  }

  Stream<List<FleetWorkRecord>> watchWorkRecords({
    String? assetId,
    String? loggedByClockNo,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q =
        _db.collection(Collections.fleetWorkRecords);
    if (assetId != null) q = q.where('asset_id', isEqualTo: assetId);
    if (loggedByClockNo != null) {
      q = q.where('logged_by_clock_no', isEqualTo: loggedByClockNo);
    }
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(FleetWorkRecord.fromFirestore).toList());
  }

  Future<FleetWorkRecord?> getWorkRecord(String id) async {
    final snap =
        await _db.collection(Collections.fleetWorkRecords).doc(id).get();
    if (!snap.exists) return null;
    return FleetWorkRecord.fromFirestore(snap);
  }

  Future<void> updateWorkRecord(
      String id, Map<String, dynamic> data) async {
    await _db
        .collection(Collections.fleetWorkRecords)
        .doc(id)
        .update({...data, 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ---------------------------------------------------------------------------
  // WORK PARTS (sub-collection)
  // ---------------------------------------------------------------------------

  Stream<List<FleetWorkPart>> watchParts(String workRecordId) {
    return _db
        .collection(Collections.fleetWorkRecords)
        .doc(workRecordId)
        .collection(Collections.fleetWorkParts)
        .orderBy('created_at')
        .snapshots()
        .map((s) => s.docs.map(FleetWorkPart.fromFirestore).toList());
  }

  Future<void> addPart(String workRecordId, FleetWorkPart part) async {
    await _db
        .collection(Collections.fleetWorkRecords)
        .doc(workRecordId)
        .collection(Collections.fleetWorkParts)
        .add(part.toFirestore());
  }

  Future<void> removePart(String workRecordId, String partId) async {
    await _db
        .collection(Collections.fleetWorkRecords)
        .doc(workRecordId)
        .collection(Collections.fleetWorkParts)
        .doc(partId)
        .delete();
  }

  Future<void> replaceParts(
      String workRecordId, List<FleetWorkPart> parts) async {
    final partsRef = _db
        .collection(Collections.fleetWorkRecords)
        .doc(workRecordId)
        .collection(Collections.fleetWorkParts);
    final existing = await partsRef.get();
    final batch = _db.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final part in parts) {
      batch.set(partsRef.doc(), part.toFirestore());
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // WORK RECORD COMMENTS (sub-collection)
  // ---------------------------------------------------------------------------

  Stream<List<FleetWorkComment>> watchComments(String workRecordId) {
    return _db
        .collection(Collections.fleetWorkRecords)
        .doc(workRecordId)
        .collection(Collections.fleetWorkComments)
        .orderBy('created_at')
        .snapshots()
        .map((s) => s.docs.map(FleetWorkComment.fromFirestore).toList());
  }

  Future<void> addComment(
      String workRecordId, FleetWorkComment comment) async {
    await _db
        .collection(Collections.fleetWorkRecords)
        .doc(workRecordId)
        .collection(Collections.fleetWorkComments)
        .add(comment.toFirestore());
  }

  // ---------------------------------------------------------------------------
  // PART NAME SUGGESTIONS (collection group across all work records)
  // ---------------------------------------------------------------------------

  Future<List<String>> getSuggestedPartNames() async {
    try {
      final snap = await _db
          .collectionGroup(Collections.fleetWorkParts)
          .limit(200)
          .get();
      final names = <String>{};
      for (final doc in snap.docs) {
        final name = doc.data()['part_name'] as String?;
        if (name != null && name.trim().isNotEmpty) names.add(name.trim());
      }
      return names.toList()..sort();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> uploadPhotosForRecord(
      String recordId, List<String> localPaths) async {
    final urls = <String>[];
    for (final path in localPaths) {
      final url = await uploadFleetPhoto(
        localPath: path,
        fleetRef: 'fleet_work_records/$recordId',
      );
      urls.add(url);
    }
    return urls;
  }

  Future<List<String>> uploadPhotosForIssue(
      String issueId, List<String> localPaths) async {
    final urls = <String>[];
    for (final path in localPaths) {
      final url = await uploadFleetPhoto(
        localPath: path,
        fleetRef: 'fleet_issues/$issueId',
      );
      urls.add(url);
    }
    return urls;
  }

  // ---------------------------------------------------------------------------
  // COST LINES
  // ---------------------------------------------------------------------------

  Future<void> createCostLine(FleetCostLine line) async {
    final batch = _db.batch();
    final lineRef = _db.collection(Collections.fleetCostLines).doc();
    batch.set(lineRef, line.toFirestore());

    // Costing the linked work record locks it for the mechanic.
    if (line.workRecordId != null) {
      final wrRef = _db
          .collection(Collections.fleetWorkRecords)
          .doc(line.workRecordId);
      batch.update(wrRef, {
        'cost_status': FleetCostStatus.costed.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Marks a work record as needing no spend (adjustments, inspections)
  /// so it leaves the costing queue. Locks mechanic edits like costing does.
  Future<void> markWorkRecordNoCost(
      String workRecordId, String clockNo, String name) async {
    final batch = _db.batch();
    batch.update(
      _db.collection(Collections.fleetWorkRecords).doc(workRecordId),
      {
        'cost_status': FleetCostStatus.noCost.value,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(_db.collection(Collections.fleetAudit).doc(), {
      'action': 'work_record_no_cost',
      'actor_clock_no': clockNo,
      'details': 'Marked work record $workRecordId as no cost needed ($name)',
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Stream<List<FleetCostLine>> watchCostLines({
    String? assetId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> q =
        _db.collection(Collections.fleetCostLines);
    if (assetId != null) q = q.where('asset_id', isEqualTo: assetId);
    if (from != null) {
      q = q.where('cost_date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('cost_date',
          isLessThanOrEqualTo: Timestamp.fromDate(to));
    }
    return q
        .orderBy('cost_date', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(FleetCostLine.fromFirestore).toList());
  }

  Future<List<FleetCostLine>> getCostLinesOnce({
    String? assetId,
    DateTime? from,
    DateTime? to,
  }) async {
    Query<Map<String, dynamic>> q =
        _db.collection(Collections.fleetCostLines);
    if (assetId != null) q = q.where('asset_id', isEqualTo: assetId);
    if (from != null) {
      q = q.where('cost_date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('cost_date',
          isLessThanOrEqualTo: Timestamp.fromDate(to));
    }
    final snap = await q.orderBy('cost_date', descending: true).get();
    return snap.docs.map(FleetCostLine.fromFirestore).toList();
  }

  Future<void> deleteCostLine(String id) async {
    final ref = _db.collection(Collections.fleetCostLines).doc(id);
    final snap = await ref.get();
    final workRecordId = snap.data()?['work_record_id'] as String?;
    await ref.delete();

    // Removing the last cost line puts the job back in the costing queue
    // (re-opens mechanic editing only if still within the edit window).
    if (workRecordId != null) {
      final remaining = await _db
          .collection(Collections.fleetCostLines)
          .where('work_record_id', isEqualTo: workRecordId)
          .limit(1)
          .get();
      if (remaining.docs.isEmpty) {
        await _db
            .collection(Collections.fleetWorkRecords)
            .doc(workRecordId)
            .update({
          'cost_status': FleetCostStatus.pending.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PHOTOS — pick → compress (1024×1024, q70) → upload to Storage
  // Mirrors WasteService photo pattern exactly.
  // ---------------------------------------------------------------------------

  Future<String?> pickAndCompressPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return null;

    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/${const Uuid().v4()}.jpg';

    final compressed = await FlutterImageCompress.compressAndGetFile(
      picked.path,
      outPath,
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
    );
    return compressed?.path;
  }

  /// Uploads a compressed photo file to Firebase Storage.
  /// [fleetRef] is e.g. "fleet_issues/abc123" or "fleet_work_records/xyz"
  Future<String> uploadFleetPhoto({
    required String localPath,
    required String fleetRef,
  }) async {
    final file = File(localPath);
    final fileName = '${const Uuid().v4()}.jpg';
    final ref = _storage.ref('$fleetRef/photos/$fileName');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }

  // ---------------------------------------------------------------------------
  // OFFLINE-FIRST — mirrors WasteService resilience pattern
  // ---------------------------------------------------------------------------

  static const Duration _photoUploadTimeout = Duration(seconds: 12);
  static const Duration _firestoreWriteTimeout = Duration(seconds: 8);
  static const Duration _callableTimeout = Duration(seconds: 15);

  Future<bool> _checkOnline() =>
      ConnectivityService().isOnline().catchError((_) => false);

  Future<void> queueOfflineFleetPhoto({
    required String localPath,
    required String targetKind,
    required String targetId,
  }) async {
    await SyncService().addToQueue(
      collection: 'fleet_photos',
      operation: 'upload',
      data: {
        'localPath': localPath,
        'targetKind': targetKind,
        'targetId': targetId,
      },
      documentId:
          '${targetKind}_${targetId}_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Creates an issue offline-first; photos queue when upload fails or offline.
  Future<({String id, bool queuedOffline})> createIssueResilient(
    FleetIssue issue, {
    List<String> photoPaths = const [],
  }) async {
    final issueId = _db.collection(Collections.fleetIssues).doc().id;
    final online = await _checkOnline();
    final base = issue.toFirestore()
      ..['status'] = 'open'
      ..['photos'] = <String>[];

    final queueData = {
      ...base,
      'created_at': DateTime.now().toIso8601String(),
    };

    await SyncService().addToQueue(
      collection: Collections.fleetIssues,
      operation: 'create',
      data: queueData,
      documentId: issueId,
    );

    for (final path in photoPaths) {
      await queueOfflineFleetPhoto(
        localPath: path,
        targetKind: 'issue',
        targetId: issueId,
      );
    }

    var queuedOffline = !online;
    if (online) {
      try {
        await _db.collection(Collections.fleetIssues).doc(issueId).set({
          ...base,
          'created_at': FieldValue.serverTimestamp(),
        }).timeout(_firestoreWriteTimeout);

        final urls = <String>[];
        for (final path in photoPaths) {
          try {
            urls.add(await uploadFleetPhoto(
              localPath: path,
              fleetRef: 'fleet_issues/$issueId',
            ).timeout(_photoUploadTimeout));
          } catch (_) {
            await queueOfflineFleetPhoto(
              localPath: path,
              targetKind: 'issue',
              targetId: issueId,
            );
          }
        }
        if (urls.isNotEmpty) {
          await _db
              .collection(Collections.fleetIssues)
              .doc(issueId)
              .update({'photos': urls});
        }
        // Direct write landed — drop the queued create so the sync replay
        // never re-writes an issue (reports are immutable once created).
        await SyncService().removeQueuedItem(
          collection: Collections.fleetIssues,
          documentId: issueId,
        );
      } catch (_) {
        queuedOffline = true;
      }
      unawaited(SyncService().processNow());
    }

    return (id: issueId, queuedOffline: queuedOffline);
  }

  /// Creates a work record via CF when online; queues create_cf when offline/slow.
  Future<({String id, String? workNumber, bool queuedOffline})>
      createWorkRecordResilient(
    Map<String, dynamic> data, {
    List<String> photoPaths = const [],
    List<FleetWorkPart> parts = const [],
    List<String> linkedIssueIds = const [],
    required String loggedByClockNo,
    required String loggedByName,
  }) async {
    final online = await _checkOnline();
    final queuePayload = Map<String, dynamic>.from(data);
    if (photoPaths.isNotEmpty) {
      queuePayload['_pending_photo_paths'] = photoPaths;
    }
    if (parts.isNotEmpty) {
      queuePayload['_parts'] = parts
          .map((p) => {
                'part_name': p.partName,
                if (p.quantity != null) 'quantity': p.quantity,
              })
          .toList();
    }
    if (linkedIssueIds.isNotEmpty) {
      queuePayload['_linked_issue_ids'] = linkedIssueIds;
      queuePayload['_resolver_clock_no'] = loggedByClockNo;
      queuePayload['_resolver_name'] = loggedByName;
    }

    final queueId = const Uuid().v4();
    await SyncService().addToQueue(
      collection: Collections.fleetWorkRecords,
      operation: 'create_cf',
      data: SyncService.sanitizeForHive(queuePayload),
      documentId: queueId,
    );

    var queuedOffline = !online;
    if (online) {
      try {
        final result = await createWorkRecord(data).timeout(_callableTimeout);
        final recordId = result['id'] as String;

        if (photoPaths.isNotEmpty) {
          final uploaded =
              await uploadPhotosForRecord(recordId, photoPaths);
          if (uploaded.isNotEmpty) {
            await updateWorkRecord(recordId, {'photos': uploaded});
          }
        }
        if (parts.isNotEmpty) {
          await replaceParts(recordId, parts);
        }
        for (final issueId in linkedIssueIds) {
          await resolveIssueWithWorkRecord(
            issueId,
            recordId,
            loggedByClockNo,
            loggedByName,
          );
        }

        await SyncService().removeQueuedItem(
          collection: Collections.fleetWorkRecords,
          documentId: queueId,
        );
        return (
          id: recordId,
          workNumber: result['work_number'] as String?,
          queuedOffline: false,
        );
      } catch (_) {
        queuedOffline = true;
      }
      unawaited(SyncService().processNow());
    }

    return (id: queueId, workNumber: null, queuedOffline: queuedOffline);
  }
}
