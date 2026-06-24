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
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_comment.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

/// Thrown when a status change loses a race — the issue moved on while this
/// screen showed a stale snapshot. toString is the user-facing message.
class FleetConflictException implements Exception {
  final String message;
  FleetConflictException(this.message);
  @override
  String toString() => message;
}

/// All Fleet Maintenance Firestore and Storage operations.
/// Follows the WasteService singleton pattern.
class FleetService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'africa-south1');

  // ---------------------------------------------------------------------------
  // AUDIT TRAIL — append-only fleet_audit (rules block update/delete).
  // Fire-and-forget: auditing must never block or fail the action it records.
  // Offline writes are buffered by the Firestore SDK and flush on reconnect.
  // ---------------------------------------------------------------------------

  void logAudit(
    String action, {
    required String actorClockNo,
    String? actorName,
    Map<String, dynamic>? details,
  }) {
    try {
      unawaited(_db.collection(Collections.fleetAudit).add({
        'action': action,
        'actor_clock_no': actorClockNo,
        if (actorName != null) 'actor_name': actorName,
        if (details != null && details.isNotEmpty) 'details': details,
        'created_at': FieldValue.serverTimestamp(),
      }).then<void>((_) {}).catchError((_) {}));
    } catch (_) {}
  }

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

  Future<void> saveSettings(
    FleetSettings settings, {
    String? actorClockNo,
    String? actorName,
  }) async {
    await _db
        .collection(Collections.fleetSettings)
        .doc('config')
        .set(settings.toFirestore(), SetOptions(merge: true));
    if (actorClockNo != null) {
      logAudit('settings_saved',
          actorClockNo: actorClockNo, actorName: actorName);
    }
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

  Stream<FleetAsset?> watchAsset(String id) {
    return _db
        .collection(Collections.fleetAssets)
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists ? FleetAsset.fromFirestore(snap) : null);
  }

  Future<void> saveAsset(
    FleetAsset asset, {
    String? actorClockNo,
    String? actorName,
  }) async {
    if (asset.id == null) {
      await _db.collection(Collections.fleetAssets).add(asset.toFirestore());
    } else {
      await _db
          .collection(Collections.fleetAssets)
          .doc(asset.id)
          .set(asset.toFirestore(), SetOptions(merge: true));
    }
    if (actorClockNo != null) {
      logAudit('asset_saved',
          actorClockNo: actorClockNo,
          actorName: actorName,
          details: {
            'asset_name': asset.name,
            'asset_tag': asset.assetTag,
            'active': asset.active,
          });
    }
  }

  /// All issues for one asset, newest first. Uses an equality-only query
  /// (auto-indexed) with a client-side sort, so no composite index is
  /// needed — at ~12 assets the per-asset issue count stays small.
  Stream<List<FleetIssue>> watchAssetIssues(String assetId) {
    return _db
        .collection(Collections.fleetIssues)
        .where('asset_id', isEqualTo: assetId)
        .snapshots()
        .map((s) {
      final issues = s.docs.map(FleetIssue.fromFirestore).toList()
        ..sort((a, b) {
          final ad = a.createdAt ?? DateTime(2000);
          final bd = b.createdAt ?? DateTime(2000);
          return bd.compareTo(ad);
        });
      return issues;
    });
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

  /// Throws [FleetConflictException] when the issue's live status is not in
  /// [allowed] — i.e. someone else changed it while this screen showed a
  /// stale snapshot. When the server can't be reached (offline) the check is
  /// skipped and the buffered write proceeds; the single-mechanic workflow
  /// makes an offline conflict effectively impossible.
  Future<void> _guardIssueStatus(
      String issueId, Set<FleetIssueStatus> allowed) async {
    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _db
          .collection(Collections.fleetIssues)
          .doc(issueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return;
    }
    if (!snap.exists) {
      throw FleetConflictException('This problem no longer exists.');
    }
    final status =
        FleetIssueStatus.fromString(snap.data()?['status'] as String?);
    if (!allowed.contains(status)) {
      throw FleetConflictException(
        'This problem is already ${status.displayLabel.toLowerCase()} — '
        'go back and reopen it to see the latest.',
      );
    }
  }

  Future<void> acknowledgeIssue(String issueId, String clockNo, String name) async {
    await _guardIssueStatus(issueId, {FleetIssueStatus.open});
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'acknowledged',
      'acknowledged_by_clock_no': clockNo,
      'acknowledged_by_name': name,
      'acknowledged_at': FieldValue.serverTimestamp(),
    });
    logAudit('issue_acknowledged',
        actorClockNo: clockNo, actorName: name, details: {'issue_id': issueId});
  }

  Future<void> resolveIssueWithNote(
      String issueId, String note, String clockNo, String name) async {
    await _guardIssueStatus(
        issueId, {FleetIssueStatus.open, FleetIssueStatus.acknowledged});
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'resolved',
      'resolution_type': 'note',
      'resolution_note': note,
      'resolved_by_clock_no': clockNo,
      'resolved_by_name': name,
      'resolved_at': FieldValue.serverTimestamp(),
    });
    logAudit('issue_resolved_note',
        actorClockNo: clockNo, actorName: name, details: {'issue_id': issueId});
  }

  /// Deliberately unguarded: a logged work record is the strongest form of
  /// resolution and may overwrite a note-resolution that raced it. Also
  /// called from the offline replay path, which must never throw conflicts.
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
    logAudit('issue_resolved_work_record',
        actorClockNo: clockNo,
        actorName: name,
        details: {'issue_id': issueId, 'work_record_id': workRecordId});
  }

  Future<void> cancelIssue(
      String issueId, String clockNo, String name, {String? reason}) async {
    await _guardIssueStatus(
        issueId, {FleetIssueStatus.open, FleetIssueStatus.acknowledged});
    await _db.collection(Collections.fleetIssues).doc(issueId).update({
      'status': 'cancelled',
      'cancelled_by_clock_no': clockNo,
      'cancelled_by_name': name,
      if (reason != null) 'cancel_reason': reason,
      'cancelled_at': FieldValue.serverTimestamp(),
    });
    logAudit('issue_cancelled',
        actorClockNo: clockNo,
        actorName: name,
        details: {'issue_id': issueId, if (reason != null) 'reason': reason});
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

  Stream<FleetWorkRecord?> watchWorkRecord(String id) {
    return _db
        .collection(Collections.fleetWorkRecords)
        .doc(id)
        .snapshots()
        .map((snap) =>
            snap.exists ? FleetWorkRecord.fromFirestore(snap) : null);
  }

  Future<void> updateWorkRecord(
    String id,
    Map<String, dynamic> data, {
    String? actorClockNo,
    String? actorName,
  }) async {
    await _db
        .collection(Collections.fleetWorkRecords)
        .doc(id)
        .update({...data, 'updatedAt': FieldValue.serverTimestamp()});
    if (actorClockNo != null) {
      logAudit('work_record_edited',
          actorClockNo: actorClockNo,
          actorName: actorName,
          details: {'work_record_id': id});
    }
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

  /// Creates a cost line offline-first — same queue-first pattern as issues.
  /// The linked work record's has_cost_lines flag is queued as a separate
  /// merge-update so it replays safely too.
  Future<({String id, bool queuedOffline})> createCostLineResilient(
      FleetCostLine line) async {
    final lineId = _db.collection(Collections.fleetCostLines).doc().id;
    final online = await _checkOnline();
    final data = line.toFirestore();

    await SyncService().addToQueue(
      collection: Collections.fleetCostLines,
      operation: 'create',
      data: SyncService.sanitizeForHive(data),
      documentId: lineId,
    );
    if (line.workRecordId != null) {
      await SyncService().addToQueue(
        collection: Collections.fleetWorkRecords,
        operation: 'update',
        data: {'has_cost_lines': true},
        documentId: line.workRecordId!,
      );
    }

    logAudit('cost_line_added',
        actorClockNo: line.enteredByClockNo,
        actorName: line.enteredByName,
        details: {
          'asset_name': line.assetName,
          'amount_zar': line.amountZar,
          if (line.workNumber != null) 'work_number': line.workNumber,
        });

    var queuedOffline = !online;
    if (online) {
      try {
        final batch = _db.batch();
        batch.set(_db.collection(Collections.fleetCostLines).doc(lineId), data);
        if (line.workRecordId != null) {
          batch.update(
            _db.collection(Collections.fleetWorkRecords).doc(line.workRecordId),
            {'has_cost_lines': true},
          );
        }
        await batch.commit().timeout(_firestoreWriteTimeout);
        queuedOffline = false;
        await SyncService().removeQueuedItem(
          collection: Collections.fleetCostLines,
          documentId: lineId,
        );
        if (line.workRecordId != null) {
          await SyncService().removeQueuedItem(
            collection: Collections.fleetWorkRecords,
            documentId: line.workRecordId!,
          );
        }
      } catch (_) {
        queuedOffline = true;
      }
      unawaited(SyncService().processNow());
    }

    return (id: lineId, queuedOffline: queuedOffline);
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

  /// Deterministic queue id per photo so a successful direct upload can
  /// dequeue its own entry, and accidental duplicates dedupe at startup.
  static String fleetPhotoQueueId({
    required String targetKind,
    required String targetId,
    required String localPath,
  }) =>
      '${targetKind}_${targetId}_${localPath.hashCode}';

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
      documentId: fleetPhotoQueueId(
        targetKind: targetKind,
        targetId: targetId,
        localPath: localPath,
      ),
    );
  }

  /// Creates an issue offline-first; photos queue when upload fails or offline.
  ///
  /// Queue bookkeeping: the create entry is removed as soon as the direct
  /// write lands (so a later replay can never overwrite status changes or
  /// photo URLs made in the meantime), and each photo entry is removed as
  /// its direct upload+patch succeeds. The replay path is additionally
  /// guarded by create-if-not-exists in SyncService.
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

    logAudit('issue_reported',
        actorClockNo: issue.reportedByClockNo,
        actorName: issue.reportedByName,
        details: {
          'issue_id': issueId,
          'asset_name': issue.assetName,
          'severity': issue.severity.value,
        });

    var queuedOffline = !online;
    if (online) {
      var docCreated = false;
      try {
        await _db.collection(Collections.fleetIssues).doc(issueId).set({
          ...base,
          'created_at': FieldValue.serverTimestamp(),
        }).timeout(_firestoreWriteTimeout);
        docCreated = true;
        await SyncService().removeQueuedItem(
          collection: Collections.fleetIssues,
          documentId: issueId,
        );
      } catch (_) {
        queuedOffline = true;
      }

      if (docCreated) {
        for (final path in photoPaths) {
          try {
            final url = await uploadFleetPhoto(
              localPath: path,
              fleetRef: 'fleet_issues/$issueId',
            ).timeout(_photoUploadTimeout);
            await _db
                .collection(Collections.fleetIssues)
                .doc(issueId)
                .update({
              'photos': FieldValue.arrayUnion([url]),
            }).timeout(_firestoreWriteTimeout);
            await SyncService().removeQueuedItem(
              collection: 'fleet_photos',
              documentId: fleetPhotoQueueId(
                targetKind: 'issue',
                targetId: issueId,
                localPath: path,
              ),
            );
          } catch (_) {
            // Entry stays queued for retry.
          }
        }
      }
      unawaited(SyncService().processNow());
    }

    return (id: issueId, queuedOffline: queuedOffline);
  }

  /// Creates a work record via CF when online; queues create_cf when offline/slow.
  ///
  /// Duplicate-safe: the queue id is passed to the CF as `client_ref`, which
  /// becomes the record's document ID — so a replayed call (lost response,
  /// force-close, failed attachment step) returns the existing record instead
  /// of minting a new FM number. After the CF succeeds, the created record id
  /// is stamped onto the queue item and per-step progress (photos, parts) is
  /// pruned from it, so a replay only resumes what's still outstanding.
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
    final queueId = const Uuid().v4();
    final cfData = Map<String, dynamic>.from(data)..['client_ref'] = queueId;

    final queuePayload = Map<String, dynamic>.from(cfData);
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

    await SyncService().addToQueue(
      collection: Collections.fleetWorkRecords,
      operation: 'create_cf',
      data: SyncService.sanitizeForHive(queuePayload),
      documentId: queueId,
    );

    // Logged at queue time (the record is guaranteed to exist via replay);
    // client_ref ties the audit entry to the eventual document.
    logAudit('work_record_created',
        actorClockNo: loggedByClockNo,
        actorName: loggedByName,
        details: {
          'client_ref': queueId,
          'asset_name': data['asset_name'],
          'title': data['title'],
        });

    if (!online) {
      return (id: queueId, workNumber: null, queuedOffline: true);
    }

    // Step 1 — create the record. On failure the queued entry replays later;
    // client_ref guarantees the replay can't duplicate it.
    String recordId;
    String? workNumber;
    try {
      final result = await createWorkRecord(cfData).timeout(_callableTimeout);
      recordId = result['id'] as String;
      workNumber = result['work_number'] as String?;
    } catch (_) {
      unawaited(SyncService().processNow());
      return (id: queueId, workNumber: null, queuedOffline: true);
    }

    await SyncService().mutateQueuedItemData(
      collection: Collections.fleetWorkRecords,
      documentId: queueId,
      mutate: (d) => d['_created_record_id'] = recordId,
    );

    // Step 2 — attachments and linked issues. Failures leave the queue item
    // in place (minus completed steps) for the replay to finish.
    var pending = false;
    for (final path in photoPaths) {
      try {
        final url = await uploadFleetPhoto(
          localPath: path,
          fleetRef: 'fleet_work_records/$recordId',
        ).timeout(_photoUploadTimeout);
        await _db
            .collection(Collections.fleetWorkRecords)
            .doc(recordId)
            .update({
          'photos': FieldValue.arrayUnion([url]),
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(_firestoreWriteTimeout);
        await SyncService().mutateQueuedItemData(
          collection: Collections.fleetWorkRecords,
          documentId: queueId,
          mutate: (d) =>
              (d['_pending_photo_paths'] as List?)?.remove(path),
        );
      } catch (_) {
        pending = true;
      }
    }

    if (parts.isNotEmpty) {
      try {
        await replaceParts(recordId, parts)
            .timeout(_firestoreWriteTimeout);
        await SyncService().mutateQueuedItemData(
          collection: Collections.fleetWorkRecords,
          documentId: queueId,
          mutate: (d) => d.remove('_parts'),
        );
      } catch (_) {
        pending = true;
      }
    }

    if (linkedIssueIds.isNotEmpty) {
      try {
        for (final issueId in linkedIssueIds) {
          await resolveIssueWithWorkRecord(
            issueId,
            recordId,
            loggedByClockNo,
            loggedByName,
          ).timeout(_firestoreWriteTimeout);
        }
        await SyncService().mutateQueuedItemData(
          collection: Collections.fleetWorkRecords,
          documentId: queueId,
          mutate: (d) => d
            ..remove('_linked_issue_ids')
            ..remove('_resolver_clock_no')
            ..remove('_resolver_name'),
        );
      } catch (_) {
        pending = true;
      }
    }

    if (pending) {
      unawaited(SyncService().processNow());
      return (id: recordId, workNumber: workNumber, queuedOffline: true);
    }

    await SyncService().removeQueuedItem(
      collection: Collections.fleetWorkRecords,
      documentId: queueId,
    );
    return (id: recordId, workNumber: workNumber, queuedOffline: false);
  }

  // ---------------------------------------------------------------------------
  // DAILY CHECKS (fleet_daily_checks)
  // ---------------------------------------------------------------------------

  Future<FleetDailyChecklistConfig> getDailyChecklistConfig() async {
    final snap = await _db
        .collection(Collections.fleetSettings)
        .doc('daily_checklist')
        .get();
    if (!snap.exists) return FleetDailyChecklistConfig.defaults;
    final config = FleetDailyChecklistConfig.fromFirestore(snap);
    if (config.items.isEmpty) {
      return FleetDailyChecklistConfig.defaults.copyWithEnabled(config.enabled);
    }
    return config;
  }

  Stream<FleetDailyChecklistConfig> watchDailyChecklistConfig() {
    return _db
        .collection(Collections.fleetSettings)
        .doc('daily_checklist')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return FleetDailyChecklistConfig.defaults;
      final config = FleetDailyChecklistConfig.fromFirestore(snap);
      if (config.items.isEmpty) {
        return FleetDailyChecklistConfig.defaults.copyWithEnabled(config.enabled);
      }
      return config;
    });
  }

  Future<FleetDailyCheck?> getDailyCheck(String assetId, [DateTime? date]) async {
    final docId = FleetDailyCheck.docIdFor(assetId, date);
    final snap =
        await _db.collection(Collections.fleetDailyChecks).doc(docId).get();
    if (!snap.exists) return null;
    return FleetDailyCheck.fromFirestore(snap);
  }

  Stream<List<FleetDailyCheck>> watchDailyChecksForDate([DateTime? date]) {
    final today = FleetDailyCheck.checkDateString(date);
    return _db
        .collection(Collections.fleetDailyChecks)
        .where('check_date', isEqualTo: today)
        .snapshots()
        .map((s) => s.docs.map(FleetDailyCheck.fromFirestore).toList());
  }

  Stream<FleetDailyCheck?> watchDailyCheck(String assetId, [DateTime? date]) {
    final docId = FleetDailyCheck.docIdFor(assetId, date);
    return _db
        .collection(Collections.fleetDailyChecks)
        .doc(docId)
        .snapshots()
        .map((snap) =>
            snap.exists ? FleetDailyCheck.fromFirestore(snap) : null);
  }

  /// Open starts (no end) for today by driver clock number.
  Stream<List<FleetDailyCheck>> watchOpenDailyChecksForDriver(String clockNo) {
    final today = FleetDailyCheck.checkDateString();
    return _db
        .collection(Collections.fleetDailyChecks)
        .where('check_date', isEqualTo: today)
        .snapshots()
        .map((s) {
      final checks = s.docs.map(FleetDailyCheck.fromFirestore).toList();
      return checks
          .where((c) => c.isOpen && c.start?.driverClockNo == clockNo)
          .toList()
        ..sort((a, b) => a.assetName.compareTo(b.assetName));
    });
  }

  Future<void> propagateMachineHoursIfHigher(
    String assetId,
    double reading, {
    String? actorClockNo,
    String? actorName,
  }) async {
    final asset = await getAsset(assetId);
    if (asset == null) return;
    final current = asset.currentMachineHours;
    if (current != null && reading < current) return;
    await _db.collection(Collections.fleetAssets).doc(assetId).set(
      {'current_machine_hours': reading},
      SetOptions(merge: true),
    );
    if (actorClockNo != null) {
      logAudit('asset_hours_updated',
          actorClockNo: actorClockNo,
          actorName: actorName,
          details: {
            'asset_id': assetId,
            'reading': reading,
            'source': 'daily_check',
          });
    }
  }

  Future<({String id, bool queuedOffline})> createDailyCheckStartResilient({
    required String assetId,
    required String assetName,
    required String assetTag,
    required String driverClockNo,
    required String driverName,
    String? department,
    required List<FleetDailyCheckItem> items,
    required double hourMeter,
    String? generalComment,
  }) async {
    final docId = FleetDailyCheck.docIdFor(assetId);
    final checkDate = FleetDailyCheck.checkDateString();
    final hasFaulty = items.any((i) => i.isFaulty);
    final clientRef = const Uuid().v4();

    final start = FleetDailyCheckStart(
      hourMeter: hourMeter,
      driverClockNo: driverClockNo,
      driverName: driverName,
      department: department,
      items: items,
      generalComment: generalComment,
    );

    final payload = {
      'asset_id': assetId,
      'asset_name': assetName,
      'asset_tag': assetTag,
      'check_date': checkDate,
      'start': {
        ...start.toMap(),
        'at': DateTime.now().toIso8601String(),
        'items': items.map((i) => i.toMap()).toList(),
      },
      'has_faulty_items': hasFaulty,
      'client_ref': clientRef,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    final online = await _checkOnline();
    await SyncService().addToQueue(
      collection: Collections.fleetDailyChecks,
      operation: 'create',
      data: SyncService.sanitizeForHive(payload),
      documentId: docId,
    );

    logAudit('daily_check_started',
        actorClockNo: driverClockNo,
        actorName: driverName,
        details: {
          'check_id': docId,
          'asset_name': assetName,
          'has_faulty_items': hasFaulty,
        });

    var queuedOffline = !online;
    if (online) {
      try {
        await _db.collection(Collections.fleetDailyChecks).doc(docId).set({
          'asset_id': assetId,
          'asset_name': assetName,
          'asset_tag': assetTag,
          'check_date': checkDate,
          'start': start.toMap(),
          'has_faulty_items': hasFaulty,
          'client_ref': clientRef,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        }).timeout(_firestoreWriteTimeout);
        await propagateMachineHoursIfHigher(
          assetId,
          hourMeter,
          actorClockNo: driverClockNo,
          actorName: driverName,
        );
        await SyncService().removeQueuedItem(
          collection: Collections.fleetDailyChecks,
          documentId: docId,
        );
      } catch (_) {
        queuedOffline = true;
        unawaited(SyncService().processNow());
      }
    }

    return (id: docId, queuedOffline: queuedOffline);
  }

  Future<({bool queuedOffline})> completeDailyCheckEndResilient({
    required String checkDocId,
    required String assetId,
    required double endHourMeter,
    required double startHourMeter,
    String? comment,
    required String driverClockNo,
    String? driverName,
  }) async {
    final hoursUsed = endHourMeter - startHourMeter;
    final end = FleetDailyCheckEnd(hourMeter: endHourMeter, comment: comment);
    final payload = {
      'end': {
        ...end.toMap(),
        'at': DateTime.now().toIso8601String(),
      },
      'hours_used': hoursUsed >= 0 ? hoursUsed : 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final online = await _checkOnline();
    await SyncService().addToQueue(
      collection: Collections.fleetDailyChecks,
      operation: 'update',
      data: SyncService.sanitizeForHive(payload),
      documentId: checkDocId,
    );

    logAudit('daily_check_ended',
        actorClockNo: driverClockNo,
        actorName: driverName,
        details: {
          'check_id': checkDocId,
          'hours_used': hoursUsed,
        });

    var queuedOffline = !online;
    if (online) {
      try {
        await _db.collection(Collections.fleetDailyChecks).doc(checkDocId).update({
          'end': end.toMap(),
          'hours_used': hoursUsed >= 0 ? hoursUsed : 0,
          'updated_at': FieldValue.serverTimestamp(),
        }).timeout(_firestoreWriteTimeout);
        await propagateMachineHoursIfHigher(
          assetId,
          endHourMeter,
          actorClockNo: driverClockNo,
          actorName: driverName,
        );
        await SyncService().removeQueuedItem(
          collection: Collections.fleetDailyChecks,
          documentId: checkDocId,
        );
      } catch (_) {
        queuedOffline = true;
        unawaited(SyncService().processNow());
      }
    }

    return (queuedOffline: queuedOffline);
  }
}
