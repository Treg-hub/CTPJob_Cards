import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assignment_event.dart';
import '../models/copper_transaction.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../constants/collections.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Parses job card docs, skipping any that fail instead of throwing.
  /// One corrupted document used to error the entire stream emission and
  /// blank every job list for every user — a skipped doc is logged to
  /// Crashlytics (non-fatal) so it can be repaired, while the rest render.
  static List<JobCard> parseJobCards(Iterable<DocumentSnapshot> docs) {
    final cards = <JobCard>[];
    for (final doc in docs) {
      try {
        cards.add(JobCard.fromFirestore(doc));
      } catch (e, st) {
        debugPrint('⚠️ Skipping unparseable job card ${doc.id}: $e');
        if (!kIsWeb) {
          try {
            FirebaseCrashlytics.instance.recordError(
              e,
              st,
              reason: 'job_card_parse_failed',
              information: ['docId:${doc.id}'],
              fatal: false,
            );
          } catch (_) {
            // Crashlytics unavailable (tests / pre-init) — the skip still works.
          }
        }
      }
    }
    return cards;
  }

  // Employee operations
  Future<Employee?> getEmployee(String clockNo) async {
    try {
      final doc = await _firestore.collection(Collections.employees).doc(clockNo).get();
      if (!doc.exists) return null;
      return Employee.fromFirestore(doc.data()!, clockNo);
    } catch (e) {
      throw Exception('Failed to load employee: $e');
    }
  }

  Future<void> updateEmployee(Employee employee) async {
    try {
      await _firestore.collection(Collections.employees).doc(employee.clockNo).set(
            employee.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      throw Exception('Failed to update employee: $e');
    }
  }

  Future<void> createEmployee(Employee employee) async {
    try {
      await _firestore.collection(Collections.employees).doc(employee.clockNo).set(employee.toFirestore());
    } catch (e) {
      throw Exception('Failed to create employee: $e');
    }
  }

  Future<void> deleteEmployee(String clockNo) async {
    try {
      await _firestore.collection(Collections.employees).doc(clockNo).delete();
    } catch (e) {
      throw Exception('Failed to delete employee: $e');
    }
  }

  Future<void> deleteAllEmployees() async {
    try {
      final snapshot = await _firestore.collection(Collections.employees).get();
      const int chunkSize = 500;
      final docs = snapshot.docs;

      for (var i = 0; i < docs.length; i += chunkSize) {
        final batch = _firestore.batch();
        final end = (i + chunkSize < docs.length) ? i + chunkSize : docs.length;
        for (var j = i; j < end; j++) {
          batch.delete(docs[j].reference);
        }
        await batch.commit();
      }
    } catch (e) {
      throw Exception('Failed to delete all employees: $e');
    }
  }

  Future<List<Employee>> getAllEmployees() async {
    try {
      final snapshot = await _firestore.collection(Collections.employees).get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromFirestore(data, doc.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to load employees: $e');
    }
  }

  Stream<List<Employee>> getEmployeesStream() {
    return _firestore.collection(Collections.employees).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromFirestore(data, doc.id);
      }).toList();
    });
  }
  
  Stream<Employee> getEmployeeStream(String clockNo) {
    return _firestore
        .collection(Collections.employees)
        .doc(clockNo)
        .snapshots()
        .map((doc) {
          final data = doc.data();
          if (data == null) {
            throw Exception('Employee not found');
          }
          return Employee.fromFirestore(data, doc.id);
        });
  }

  // Job Card operations
  /// Creates a job card via the `createJobCard` Cloud Function, which atomically
  /// assigns the next number and writes the doc with the Admin SDK. The old
  /// client-side `counters` transaction is gone — `counters` is now locked
  /// (Wave B). Requires connectivity; offline creation is handled upstream in
  /// [saveJobCardOfflineAware].
  Future<void> createJobCard(JobCard jobCard, {String? clientRef}) async {
    try {
      final payload = jobCard.toCreatePayload();
      // Idempotency: a stable client_ref becomes the doc ID server-side, so a
      // retried submit (lost response, reconnect) returns the existing job
      // instead of minting a duplicate job + number.
      if (clientRef != null && clientRef.isNotEmpty) payload['client_ref'] = clientRef;
      await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('createJobCard')
          .call(payload);
    } catch (e) {
      throw Exception('Failed to create job card: $e');
    }
  }

  /// Updates ONLY the current user's own presence fields via the
  /// `updateEmployeePresence` Cloud Function (the `employees` collection is
  /// locked to admin/CF writes under Wave B). Non-fatal: presence is best-effort
  /// and must never break login, geofencing, or token refresh.
  Future<void> updateMyPresence({String? fcmToken, bool? isOnSite, Map<String, dynamic>? permissions, String? source}) async {
    final payload = <String, dynamic>{};
    if (fcmToken != null) payload['fcmToken'] = fcmToken;
    if (isOnSite != null) payload['isOnSite'] = isOnSite;
    if (permissions != null) payload['permissions'] = permissions;
    if (payload.isEmpty) return;
    // `source` tags the presence change in app_geofence (the CF logs the
    // enter/exit). Only meaningful alongside an isOnSite change.
    if (source != null && isOnSite != null) payload['source'] = source;
    try {
      await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('updateEmployeePresence')
          .call(payload);
    } catch (e) {
      debugPrint('updateMyPresence failed (non-fatal): $e');
    }
  }

  /// Admin-only direct presence write (the admin On-Site toggle). Admins carry
  /// the isAdmin claim, so this is permitted under the Wave B employees lock.
  /// Stamps the matching timestamp and logs an `admin_manual` event so the
  /// central audit stays complete.
  Future<void> adminSetPresence(String clockNo, bool isOnSite) async {
    try {
      await _firestore.collection(Collections.employees).doc(clockNo).set({
        'isOnSite': isOnSite,
        'presenceSource': 'admin_manual',
        'presenceUpdatedAt': FieldValue.serverTimestamp(),
        if (isOnSite) 'lastOnSiteAt': FieldValue.serverTimestamp()
        else 'lastOffSiteAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await logGeoFenceEvent(
        clockNo: clockNo,
        eventType: isOnSite ? 'enter' : 'exit',
        source: 'admin_manual',
      );
    } catch (e) {
      debugPrint('adminSetPresence failed: $e');
      rethrow;
    }
  }

  /// Links the current Firebase Auth account to an employee doc (by clock no)
  /// via the `linkEmployeeAccount` Cloud Function — used at registration and
  /// login self-heal in place of the old direct `uid` write to `employees`.
  /// Throws on failure so registration can surface it.
  Future<void> linkMyAccount(String clockNo, {String? email}) async {
    await FirebaseFunctions.instanceFor(region: 'africa-south1')
        .httpsCallable('linkEmployeeAccount')
        .call({'clockNo': clockNo, if (email != null) 'email': email});
  }

  /// Points an employee's notifications at this device by setting only their
  /// fcmToken, via the `setDeviceFcmToken` Cloud Function. Used by the
  /// shared-device "switch user" flow (the employees collection is locked to
  /// admin/CF writes under Wave B).
  Future<void> setDeviceFcmToken(String clockNo, String fcmToken) async {
    await FirebaseFunctions.instanceFor(region: 'africa-south1')
        .httpsCallable('setDeviceFcmToken')
        .call({'clockNo': clockNo, 'fcmToken': fcmToken});
  }

  Future<void> updateJobCard(String jobCardId, JobCard jobCard) async {
    try {
      // Exclude photos so a routine merge-set does not clobber concurrent
      // arrayUnion/arrayRemove writes to the photos field. Photo mutations go
      // through addPhotoToJobCard / removePhotoFromJobCard below.
      await _firestore
          .collection(Collections.jobCards)
          .doc(jobCardId)
          .set(jobCard.toFirestore(includePhotos: false), SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update job card: $e');
    }
  }

  /// Change a job card's [type] in place, reset escalation, and append a
  /// type-change entry to assignmentHistory.
  ///
  /// Clearing `notifiedAtStage1..4` lets the existing escalation function
  /// re-stamp from the next tick with the new routing. `escalationStopped`
  /// stays untouched — if the job was already assigned, escalation remains
  /// stopped (which is correct). The cloud function `onJobCardTypeChanged`
  /// picks up the type delta and notifies the new audience.
  Future<void> changeJobCardType({
    required String jobCardId,
    required JobType from,
    required JobType to,
    required Employee by,
  }) async {
    if (from == to) return;
    try {
      final event = AssignmentEvent(
        assignedByName: by.name,
        assignedByClockNo: by.clockNo,
        assigneeClockNos: const [],
        assigneeNames: const [],
        timestamp: DateTime.now(),
        typeChangedFrom: from.name,
        typeChangedTo: to.name,
      );
      await _firestore.collection(Collections.jobCards).doc(jobCardId).update({
        'type': to.name,
        'notifiedAtStage1': null,
        'notifiedAtStage2': null,
        'notifiedAtStage3': null,
        'notifiedAtStage4': null,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'assignmentHistory': FieldValue.arrayUnion([event.toFirestore()]),
      });
    } catch (e) {
      throw Exception('Failed to change job card type: $e');
    }
  }

  /// Manager status override. Field-scoped update (no whole-doc merge) that
  /// also keeps the lifecycle timestamps coherent:
  ///  - closed  → stamps closedAt (Job History / closed queries order on it)
  ///              and completedBy/completedAt when missing
  ///  - monitor → stamps monitoringStartedAt, clears closedAt
  ///  - open    → clears all completion fields so a reopened job doesn't show
  ///              a stale "Completed by"
  /// Appends a status-change event to assignmentHistory via arrayUnion.
  Future<void> changeJobCardStatus({
    required String jobCardId,
    required JobCard current,
    required JobStatus to,
    required String byName,
    required String byClockNo,
  }) async {
    try {
      final now = DateTime.now();
      final event = AssignmentEvent(
        assignedByName: 'Status → ${to.displayName} by $byName',
        assignedByClockNo: byClockNo,
        assigneeClockNos: const [],
        assigneeNames: const [],
        timestamp: now,
      );
      final update = <String, dynamic>{
        'status': to.name,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'assignmentHistory': FieldValue.arrayUnion([event.toFirestore()]),
      };
      switch (to) {
        case JobStatus.closed:
          update['closedAt'] = Timestamp.fromDate(now);
          if (current.completedAt == null) {
            update['completedAt'] = Timestamp.fromDate(now);
          }
          if (current.completedBy == null || current.completedBy!.isEmpty) {
            update['completedBy'] = byName;
          }
          update['monitoringStartedAt'] = FieldValue.delete();
          break;
        case JobStatus.monitor:
          update['monitoringStartedAt'] = Timestamp.fromDate(now);
          update['closedAt'] = FieldValue.delete();
          break;
        case JobStatus.open:
        case JobStatus.inProgress:
          update['completedBy'] = FieldValue.delete();
          update['completedAt'] = FieldValue.delete();
          update['closedAt'] = FieldValue.delete();
          update['monitoringStartedAt'] = FieldValue.delete();
          break;
      }
      await _firestore
          .collection(Collections.jobCards)
          .doc(jobCardId)
          .update(update);
    } catch (e) {
      throw Exception('Failed to change job card status: $e');
    }
  }

  /// Atomically append a photo entry to `job_cards/{jobCardId}.photos`.
  ///
  /// Uses [FieldValue.arrayUnion] so concurrent additions from multiple
  /// clients (or from offline queues replaying) all land without overwriting
  /// each other.
  Future<void> addPhotoToJobCard(String jobCardId, Map<String, dynamic> photo) async {
    try {
      await _firestore.collection(Collections.jobCards).doc(jobCardId).update({
        'photos': FieldValue.arrayUnion([photo]),
      });
    } catch (e) {
      throw Exception('Failed to add photo: $e');
    }
  }

  /// Atomically remove a photo entry from `job_cards/{jobCardId}.photos`.
  ///
  /// [photo] must be the exact map that was stored — Firestore arrayRemove
  /// requires a deep equality match.
  Future<void> removePhotoFromJobCard(String jobCardId, Map<String, dynamic> photo) async {
    try {
      await _firestore.collection(Collections.jobCards).doc(jobCardId).update({
        'photos': FieldValue.arrayRemove([photo]),
      });
    } catch (e) {
      throw Exception('Failed to remove photo: $e');
    }
  }

  Future<void> deleteJobCard(String jobCardId) async {
    try {
      await _firestore.collection(Collections.jobCards).doc(jobCardId).delete();
    } catch (e) {
      throw Exception('Failed to delete job card: $e');
    }
  }

  Future<JobCard?> getJobCard(String jobCardId) async {
    try {
      final doc = await _firestore.collection(Collections.jobCards).doc(jobCardId).get();
      if (!doc.exists) return null;
      return JobCard.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to get job card: $e');
    }
  }

  Stream<JobCard> getJobCardStream(String jobCardId) {
    return _firestore.collection(Collections.jobCards).doc(jobCardId).snapshots().map((doc) => JobCard.fromFirestore(doc));
  }

  /// Open + in-progress job cards in one listener (halves Firestore reads vs
  /// separate status streams). Matches CTP Pulse [useOpenJobCards] pattern.
  Stream<List<JobCard>> getActiveJobCards() {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', whereIn: ['open', 'inProgress'])
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  Stream<List<JobCard>> getOpenJobCards() {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  Stream<List<JobCard>> getAssignedJobCards(String employeeClockNo) {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: 'open')
        .where('assignedClockNos', arrayContains: employeeClockNo)
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  Stream<List<JobCard>> getMyJobCards(String clockNo) {
    final controller = StreamController<List<JobCard>>();

    List<JobCard> assignedJobs = [];
    List<JobCard> createdJobs = [];

    void emit() {
      final assignedIds = assignedJobs.map((j) => j.id!).toSet();
      controller.add([
        ...assignedJobs,
        ...createdJobs.where((j) => !assignedIds.contains(j.id)),
      ]);
    }

    final s1 = _firestore
        .collection(Collections.jobCards)
        .where('assignedClockNos', arrayContains: clockNo)
        .snapshots()
        .listen((snap) {
      assignedJobs = parseJobCards(snap.docs);
      emit();
    });

    final s2 = _firestore
        .collection(Collections.jobCards)
        .where('operatorClockNo', isEqualTo: clockNo)
        .snapshots()
        .listen((snap) {
      createdJobs = parseJobCards(snap.docs);
      emit();
    });

    controller.onCancel = () {
      s1.cancel();
      s2.cancel();
    };

    return controller.stream;
  }

  Stream<List<JobCard>> getCompletedJobCards() {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: 'closed')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  /// Stream of job cards, newest first. Pass [limit] wherever the consumer
  /// doesn't genuinely need the full history — the unbounded form streams
  /// every job card ever created (with embedded photo arrays) on every open.
  Stream<List<JobCard>> getAllJobCards({int? limit}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(Collections.jobCards)
        .orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snapshot) => parseJobCards(snapshot.docs));
  }

  /// Server-filtered single-status stream. Equality-only (no orderBy) so it
  /// needs no composite index — active-status sets are small and consumers
  /// sort client-side. For closed jobs use [getClosedJobCards] (indexed on
  /// closedAt) instead.
  Stream<List<JobCard>> getJobCardsByStatus(JobStatus status, {int limit = 300}) {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: status.name)
        .limit(limit)
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  /// Daily Review scope: everything active plus jobs closed in the last
  /// [closedWindow]. Replaces streaming the entire collection — closed jobs
  /// older than the window have either been reviewed or never will be.
  Stream<List<JobCard>> getActiveAndRecentlyClosedJobCards({
    Duration closedWindow = const Duration(days: 14),
  }) {
    final controller = StreamController<List<JobCard>>();

    var open = <JobCard>[];
    var inProgress = <JobCard>[];
    var monitor = <JobCard>[];
    var closed = <JobCard>[];

    void emit() {
      controller.add([...open, ...inProgress, ...monitor, ...closed]);
    }

    final subs = <StreamSubscription>[
      getJobCardsByStatus(JobStatus.open).listen((j) {
        open = j;
        emit();
      }, onError: controller.addError),
      getJobCardsByStatus(JobStatus.inProgress).listen((j) {
        inProgress = j;
        emit();
      }, onError: controller.addError),
      getJobCardsByStatus(JobStatus.monitor).listen((j) {
        monitor = j;
        emit();
      }, onError: controller.addError),
      _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'closed')
          .where('closedAt',
              isGreaterThanOrEqualTo:
                  Timestamp.fromDate(DateTime.now().subtract(closedWindow)))
          .orderBy('closedAt', descending: true)
          .snapshots()
          .map((snapshot) => parseJobCards(snapshot.docs))
          .listen((j) {
        closed = j;
        emit();
      }, onError: controller.addError),
    ];

    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };

    return controller.stream;
  }

  // ============================================================
    // TEST VERSION - WITHOUT jobCardNumber FILTER
    // Use this temporarily to debug
    // ============================================================

    /// 1. Exact Related Jobs
    Stream<List<JobCard>> getExactRelatedJobCardsStream({
      required String department,
      required String area,
      required String machine,
      required String part,
      required String type,
    }) {
      return _firestore
          .collection(Collections.jobCards)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('part', isEqualTo: part)
          .where('type', isEqualTo: type)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => parseJobCards(snapshot.docs));
    }

    /// 2. Similar Jobs (Excluding Part)
    Stream<List<JobCard>> getRelatedExcludingPartStream({
      required String department,
      required String area,
      required String machine,
      required String type,
    }) {
      return _firestore
          .collection(Collections.jobCards)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('type', isEqualTo: type)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => parseJobCards(snapshot.docs));
    }

    /// 2. Exact All Types (same dept/area/machine/part, different type)
    Stream<List<JobCard>> getExactAllTypesStream({
      required String department,
      required String area,
      required String machine,
      required String part,
    }) {
      return _firestore
          .collection(Collections.jobCards)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('part', isEqualTo: part)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => parseJobCards(snapshot.docs));
    }

    /// 3. All Parts (same dept/area/machine, different part, all types)
    Stream<List<JobCard>> getAllPartsStream({
      required String department,
      required String area,
      required String machine,
    }) {
      return _firestore
          .collection(Collections.jobCards)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => parseJobCards(snapshot.docs));
    }

  Future<List<JobCard>> getAllJobCardsFuture() async {
    try {
      final snapshot = await _firestore.collection(Collections.jobCards).limit(1000).get();
      return parseJobCards(snapshot.docs);
    } catch (e) {
      throw Exception('Failed to get all job cards: $e');
    }
  }

  /// Paginated admin fetch — newest first, 50 records per page.
  /// Uses a single-field `createdAt DESC` index (no composite needed).
  /// Pass [startAfter] as the cursor from the previous page.
  Future<({List<JobCard> cards, DocumentSnapshot? lastDoc, bool hasMore})>
      fetchAdminJobCardsPage({
    DocumentSnapshot? startAfter,
    int pageSize = 50,
  }) async {
    var query = _firestore
        .collection(Collections.jobCards)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snap = await query.get();
    return (
      cards: parseJobCards(snap.docs),
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
      hasMore: snap.docs.length == pageSize,
    );
  }

  Future<List<String>> getDepartmentsForJobCards(String status) async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: status)
          .get();

      final departments = <String>{};
      for (var doc in snapshot.docs) {
        final dept = doc['department'] as String?;
        if (dept != null && dept.isNotEmpty) departments.add(dept);
      }
      return departments.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load departments: $e');
    }
  }

  Future<List<String>> getAreasForJobCards(String status, String department) async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: status)
          .where('department', isEqualTo: department)
          .get();

      final areas = <String>{};
      for (var doc in snapshot.docs) {
        final area = doc['area'] as String?;
        if (area != null && area.isNotEmpty) areas.add(area);
      }
      return areas.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load areas: $e');
    }
  }

  Future<List<String>> getMachinesForJobCards(String status, String department, String area) async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: status)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .get();

      final machines = <String>{};
      for (var doc in snapshot.docs) {
        final machine = doc['machine'] as String?;
        if (machine != null && machine.isNotEmpty) machines.add(machine);
      }
      return machines.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load machines: $e');
    }
  }

  Future<List<String>> getPreviousParts(String department, String area, String machine) async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .get();

      final parts = snapshot.docs
          .map((doc) => (doc.data()['part'] as String? ?? '').trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .toList();
      return parts;
    } catch (e) {
      throw Exception('Failed to load previous parts: $e');
    }
  }

  // Factory structure operations
  Future<Map<String, dynamic>> getFactoryStructure() async {
    try {
      final doc = await _firestore.collection(Collections.structures).doc('factory').get();
      return doc.data()?['data'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      throw Exception('Failed to load factory structure: $e');
    }
  }

  Future<void> updateFactoryStructure(Map<String, dynamic> structure) async {
    try {
      await _firestore.collection(Collections.structures).doc('factory').set({'data': structure});
    } catch (e) {
      throw Exception('Failed to update factory structure: $e');
    }
  }

  // Settings operations
  Future<void> initializeSettings() async {
    try {
      final doc = await _firestore.collection(Collections.settings).doc('app').get();
      
      if (doc.exists) {
        debugPrint('Settings loaded successfully');
      } else {
        debugPrint('Warning: settings/app document does not exist');
      }
    } catch (e) {
      debugPrint('Warning: Could not load settings: $e');
      // Do NOT throw - let the app continue
    }
  }

  Future<String> getSwitchUserPassword() async {
    try {
      final doc = await _firestore.collection(Collections.settings).doc('app').get();
      return doc.data()?['switchUserPassword'] as String? ?? 'admin123';
    } catch (e) {
      throw Exception('Failed to get switch user password: $e');
    }
  }

  Future<void> updateSwitchUserPassword(String newPassword) async {
    try {
      await _firestore.collection(Collections.settings).doc('app').set({
        'switchUserPassword': newPassword,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update switch user password: $e');
    }
  }

  Future<Map<String, dynamic>> getNotificationConfig() async {
    try {
      final doc = await _firestore.collection(Collections.notificationConfigs).doc('global').get();
      if (doc.exists) return doc.data()!;
    } catch (e) {
      throw Exception('Failed to get notification config: $e');
    }
    return {
      'escalation_onsite_short_minutes': 2,
      'escalation_onsite_long_minutes': 7,
      'escalation_offsite_minutes': 30,
      'escalation_stage4_minutes': 60,
      'stage1_recipients': ['onsite_managers', 'foremen'],
      'stage2_recipients': ['onsite_dept_managers', 'onsite_workshop_manager'],
      'stage3_recipients': <String>[],
      'stage4_recipients': <String>[],
    };
  }

  Future<void> saveNotificationConfig(Map<String, dynamic> config) async {
    try {
      await _firestore.collection(Collections.notificationConfigs).doc('global').set(config);
    } catch (e) {
      throw Exception('Failed to save notification config: $e');
    }
  }

  Future<String?> getCopperPassword() async {
    try {
      final doc = await _firestore.collection(Collections.settings).doc('app').get();
      return doc.data()?['copperPassword'] as String?;
    } catch (e) {
      throw Exception('Failed to get copper password: $e');
    }
  }

  // Authentication persistence
  Future<void> saveLoggedInEmployee(String clockNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loggedInClockNo', clockNo);
  }

  Future<String?> getLoggedInEmployeeClockNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loggedInClockNo');
  }

  Future<void> clearLoggedInEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedInClockNo');
  }

  // Dashboard aggregation methods
  Future<int> getOpenJobCardsCount() async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'open')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      throw Exception('Failed to get open job cards count: $e');
    }
  }

  Future<int> getCompletedJobCardsCountInPeriod(DateTime startDate) async {
    try {
      final startTimestamp = Timestamp.fromDate(startDate);
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'closed')
          .where('completedAt', isGreaterThanOrEqualTo: startTimestamp)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      throw Exception('Failed to get completed job cards count: $e');
    }
  }

  Future<Map<String, int>> getEmployeePerformance() async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'closed')
          .get();

      final performance = <String, int>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final completedBy = data['completedBy'] as String?;
        if (completedBy != null && completedBy.isNotEmpty) {
          performance[completedBy] = (performance[completedBy] ?? 0) + 1;
        }
      }
      return performance;
    } catch (e) {
      throw Exception('Failed to get employee performance: $e');
    }
  }

  Future<Duration?> getAverageCompletionTime() async {
    try {
      // Get all completed job cards and filter in memory to avoid composite index requirement
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'closed')
          .get();

      if (snapshot.docs.isEmpty) return null;

      var totalDuration = Duration.zero;
      var count = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

        if (createdAt != null && completedAt != null) {
          totalDuration += completedAt.difference(createdAt);
          count++;
        }
      }

      return count > 0 ? totalDuration ~/ count : null;
    } catch (e) {
      throw Exception('Failed to get average completion time: $e');
    }
  }

  Future<Map<String, int>> getJobCardsByPriority() async {
    try {
      final snapshot = await _firestore.collection(Collections.jobCards).get();

      final priorityCounts = <String, int>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final priority = data['priority'] as int? ?? 3;
        final status = data['status'] as String? ?? 'open';

        final key = status == 'open' ? 'Open P$priority' : 'Completed P$priority';
        priorityCounts[key] = (priorityCounts[key] ?? 0) + 1;
      }
      return priorityCounts;
    } catch (e) {
      throw Exception('Failed to get job cards by priority: $e');
    }
  }

  Future<Map<String, int>> getJobCardsByType() async {
    try {
      final snapshot = await _firestore.collection(Collections.jobCards).get();

      final typeCounts = <String, int>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? 'Mechanical';
        final status = data['status'] as String? ?? 'open';

        final key = status == 'open' ? 'Open $type' : 'Completed $type';
        typeCounts[key] = (typeCounts[key] ?? 0) + 1;
      }
      return typeCounts;
    } catch (e) {
      throw Exception('Failed to get job cards by type: $e');
    }
  }

  Stream<List<JobCard>> getMonitoringJobCards() {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: 'monitor')
        .orderBy('monitoringStartedAt', descending: false)
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  Future<List<JobCard>> getRecentlyAutoClosed(DateTime startDate) async {
    try {
      final snapshot = await _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'closed')
          .where('closedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .orderBy('closedAt', descending: true)
          .get();
      return parseJobCards(snapshot.docs);
    } catch (e) {
      throw Exception('Failed to get recently auto-closed jobs: $e');
    }
  }

  Stream<List<JobCard>> getClosedJobCards({int? limit}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: 'closed')
        .orderBy('closedAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snapshot) => parseJobCards(snapshot.docs));
  }

  Stream<List<JobCard>> getInProgressJobCards() {
    return _firestore
        .collection(Collections.jobCards)
        .where('status', isEqualTo: 'inProgress')
        .snapshots()
        .map((snapshot) => parseJobCards(snapshot.docs));
  }

  /// Server-side filtered one-shot fetch for job card history.
  ///
  /// Always filters by status=closed. Additional equality filters are applied
  /// server-side before any date-range filter, minimising document reads.
  /// [type] and [priority] are applied client-side to avoid a combinatorial
  /// explosion of composite indexes.
  ///
  /// Required Firestore indexes (deploy with firebase deploy --only firestore):
  ///   status ASC + closedAt DESC                                   (base)
  ///   status ASC + department ASC + closedAt DESC
  ///   status ASC + department ASC + area ASC + closedAt DESC
  ///   status ASC + department ASC + area ASC + machine ASC + closedAt DESC
  Future<List<JobCard>> searchClosedJobCards({
    String? department,
    String? area,
    String? machine,
    JobType? type,
    int? priority,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(Collections.jobCards)
          .where('status', isEqualTo: 'closed');

      if (department != null) query = query.where('department', isEqualTo: department);
      if (area != null && department != null) query = query.where('area', isEqualTo: area);
      if (machine != null && area != null && department != null) {
        query = query.where('machine', isEqualTo: machine);
      }

      // Date range must order by the same field
      if (fromDate != null) {
        query = query.where('closedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate));
      }
      if (toDate != null) {
        query = query.where('closedAt', isLessThanOrEqualTo: Timestamp.fromDate(toDate));
      }

      query = query.orderBy('closedAt', descending: true).limit(limit);
      if (startAfter != null) query = query.startAfterDocument(startAfter);

      final snapshot = await query.get();
      var results = parseJobCards(snapshot.docs);

      // Client-side filters to avoid additional composite indexes
      if (type != null) results = results.where((j) => j.type == type).toList();
      if (priority != null) results = results.where((j) => j.priority == priority).toList();

      return results;
    } catch (e) {
      throw Exception('Failed to search job card history: $e');
    }
  }

  // Copper transaction operations
  Future<void> createCopperTransaction(CopperTransaction transaction) async {
    try {
      await _firestore.collection(Collections.copperTransactions).doc(transaction.id).set(transaction.toFirestore());
    } catch (e) {
      throw Exception('Failed to create copper transaction: $e');
    }
  }

  // Offline-aware save for Job Cards
  Future<void> saveJobCardOfflineAware(JobCard jobCard, {String? clientRef}) async {
    final isOnline = await ConnectivityService().isOnline();

    if (isOnline) {
      if (jobCard.id == null) {
        await createJobCard(jobCard, clientRef: clientRef);
      } else {
        await updateJobCard(jobCard.id!, jobCard);
      }
      debugPrint('✅ JobCard saved directly to Firestore');
    } else {
      if (jobCard.id != null) {
        await SyncService().addToQueue(
          collection: Collections.jobCards,
          operation: 'update',
          data: jobCard.toFirestore(includePhotos: false),
          documentId: jobCard.id,
        );
        debugPrint('📤 JobCard queued for later sync (offline)');
      } else {
        debugPrint('❌ Cannot save new JobCard offline - requires online connection');
        throw Exception('Cannot create new job card offline');
      }
    }
  }

  // Offline-aware save for Copper Transactions
  Future<void> saveCopperTransactionOfflineAware(CopperTransaction transaction) async {
    final isOnline = await ConnectivityService().isOnline();

    if (isOnline) {
      await createCopperTransaction(transaction);
      debugPrint('✅ CopperTransaction saved directly to Firestore');
    } else {
      await SyncService().addToQueue(
        collection: Collections.copperTransactions,
        operation: 'create',
        data: transaction.toFirestore(),
        documentId: transaction.id,
      );
      debugPrint('📤 CopperTransaction queued for later sync (offline)');
    }
  }

  // ==================== DAILY REVIEW ====================
  Future<void> markJobCardsReviewed(List<String> jobCardIds, String managerClockNo) async {
    if (jobCardIds.isEmpty) return;
    try {
      const batchSize = 500;
      for (var i = 0; i < jobCardIds.length; i += batchSize) {
        final batch = _firestore.batch();
        final end = (i + batchSize < jobCardIds.length) ? i + batchSize : jobCardIds.length;
        for (var j = i; j < end; j++) {
          batch.update(
            _firestore.collection(Collections.jobCards).doc(jobCardIds[j]),
            {'reviewedBy.$managerClockNo': FieldValue.serverTimestamp()},
          );
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Failed to mark job cards as reviewed: $e');
    }
  }

  // ==================== CENTRAL GEOFENCE/PRESENCE EVENT LOGGING ====================
  // Single source of truth: Collections.appGeofence ('app_geofence'). Used for
  // 'check' heartbeats (WorkManager no-change ticks) and manual tests. Enter/exit
  // transitions routed through the CF are logged server-side by
  // updateEmployeePresence; native enter/exit are logged by GeofenceReceiver.kt
  // directly.
  Future<void> logGeoFenceEvent({
    required String clockNo,
    required String eventType, // 'enter' | 'exit' | 'check'
    required String source,    // 'workmanager_30min', 'app_open_check', 'manual_test', 'admin_manual', …
    double? latitude,
    double? longitude,
    double? accuracy,
    double? radiusUsed,
    String? notes,
  }) async {
    try {
      await _firestore.collection(Collections.appGeofence).add({
        'timestamp': FieldValue.serverTimestamp(),
        'clockNo': clockNo,
        'eventType': eventType,
        'source': source,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'radiusUsed': radiusUsed,
        'notes': notes ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('📍 [app_geofence] $eventType logged for $clockNo via $source');
    } catch (e) {
      debugPrint('❌ Failed to log geofence event: $e');
    }
  }
}
