import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../utils/role.dart';
import '../utils/work_report_inclusion.dart';
import '../utils/work_report_period_utils.dart';

class WorkReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  Map<String, dynamic> _periodBounds(
    String periodKey,
    WorkReportSettings settings,
  ) {
    final mode = settings.defaultPeriodMode;
    final day = settings.periodStartDay;
    return {
      'start': WorkReportPeriodUtils.periodStart(
        periodKey,
        periodMode: mode,
        periodStartDay: day,
      ),
      'end': WorkReportPeriodUtils.periodEnd(
        periodKey,
        periodMode: mode,
        periodStartDay: day,
      ),
    };
  }

  Stream<WorkReportSettings> watchSettings() {
    return _db
        .collection(Collections.workReportSettings)
        .doc('config')
        .snapshots()
        .map((snap) => WorkReportSettings.fromFirestore(snap));
  }

  Stream<WorkReportPeriod?> watchPeriod(String clockNo, String periodKey) {
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    return _db
        .collection(Collections.workReportPeriods)
        .doc(id)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return WorkReportPeriod.fromFirestore(snap.id, snap.data()!);
    });
  }

  Stream<List<WorkReportJobLine>> watchJobLines(
    String clockNo,
    String periodKey,
  ) {
    return _db
        .collection(Collections.workReportJobLines)
        .where('clockNo', isEqualTo: clockNo)
        .where('periodKey', isEqualTo: periodKey)
        .snapshots()
        .map((snap) {
      final lines = snap.docs
          .map((d) => WorkReportJobLine.fromFirestore(d.id, d.data()))
          .toList();
      lines.sort((a, b) {
        final da = a.workDate;
        final db = b.workDate;
        if (da != null && db != null) {
          final c = db.compareTo(da);
          if (c != 0) return c;
        } else if (da != null) {
          return -1;
        } else if (db != null) {
          return 1;
        }
        return b.jobCardNumber.compareTo(a.jobCardNumber);
      });
      return lines;
    });
  }

  /// Last successful candidate pull (per clock) — avoids re-pull on rebuild.
  static final Map<String, ({DateTime at, List<JobCard> jobs})> _candidateCache =
      {};
  static const _candidateCacheTtl = Duration(minutes: 5);
  static DateTime? _lastRefreshStarted;

  /// Candidate jobs: one-shot, debounced, session-cached for multi-worker scale.
  Future<List<JobCard>> fetchCandidateJobCards(
    String clockNo, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force) {
      final cached = _candidateCache[clockNo];
      if (cached != null && now.difference(cached.at) < _candidateCacheTtl) {
        return cached.jobs;
      }
    }
    // Debounce concurrent refresh storms (multi-tap).
    if (_lastRefreshStarted != null &&
        now.difference(_lastRefreshStarted!) < const Duration(seconds: 3) &&
        !force) {
      final cached = _candidateCache[clockNo];
      if (cached != null) return cached.jobs;
    }
    _lastRefreshStarted = now;

    final byId = <String, JobCard>{};

    Future<void> mergeQuery(Query<Map<String, dynamic>> q) async {
      try {
        final snap = await q.get();
        for (final job in FirestoreService.parseJobCards(snap.docs)) {
          if (job.id != null) byId[job.id!] = job;
        }
      } catch (e) {
        debugPrint('Work report candidate query failed: $e');
      }
    }

    // Caps keep cost predictable as more workers use My Timesheet.
    await Future.wait([
      mergeQuery(
        _db
            .collection(Collections.jobCards)
            .where('assignedClockNos', arrayContains: clockNo)
            .limit(250),
      ),
      mergeQuery(
        _db
            .collection(Collections.jobCards)
            .where('operatorClockNo', isEqualTo: clockNo)
            .limit(150),
      ),
    ]);

    try {
      final myWork = await FirestoreService()
          .getMyJobCards(clockNo)
          .first
          .timeout(const Duration(seconds: 12));
      for (final job in myWork) {
        if (job.id != null) byId[job.id!] = job;
      }
    } catch (e) {
      debugPrint('Work report My Work merge failed: $e');
    }

    final list = byId.values.toList();
    _candidateCache[clockNo] = (at: DateTime.now(), jobs: list);
    return list;
  }

  Future<void> ensurePeriodHeader({
    required String clockNo,
    required String periodKey,
    required Employee subject,
    required Employee actor,
    WorkReportSettings? settings,
  }) async {
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    final ref = _db.collection(Collections.workReportPeriods).doc(id);
    final existing = await ref.get();
    if (existing.exists) return;

    final s = settings ?? WorkReportSettings.defaults;
    final bounds = _periodBounds(periodKey, s);

    final payload = {
      'clockNo': clockNo,
      'periodKey': periodKey,
      'periodStart': Timestamp.fromDate(bounds['start'] as DateTime),
      'periodEnd': Timestamp.fromDate(bounds['end'] as DateTime),
      'employeeName': subject.name,
      'department': subject.department,
      'position': subject.position,
      'totalJobHours': 0,
      'totalAdditionalHours': 0,
      'totalHours': 0,
      'pdfVersion': 0,
      'lastUpdatedByClockNo': actor.clockNo,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    };
    await _writeDoc(
      collection: Collections.workReportPeriods,
      docId: id,
      operation: 'set',
      data: payload,
      merge: true,
    );
  }

  /// Prefer server CF when online; fall back to client inclusion.
  Future<int> refreshJobLines({
    required String clockNo,
    required String periodKey,
    required WorkReportSettings settings,
    required Employee subject,
    required Employee actor,
    bool preferCloudFunction = true,
  }) async {
    final online = await ConnectivityService().isOnline();
    if (preferCloudFunction && online) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
            .httpsCallable('refreshWorkReportJobLines');
        final result = await callable.call(<String, dynamic>{
          'clockNo': clockNo,
          'periodKey': periodKey,
        });
        final data = result.data;
        if (data is Map) {
          final added = data['added'];
          if (added is int) return added;
          if (added is num) return added.toInt();
        }
        return 0;
      } catch (e) {
        debugPrint('refreshWorkReportJobLines CF failed, client fallback: $e');
      }
    }
    return _refreshJobLinesClient(
      clockNo: clockNo,
      periodKey: periodKey,
      settings: settings,
      subject: subject,
      actor: actor,
    );
  }

  /// Re-runs inclusion; adds new lines; marks stale lines orphan (keeps hours).
  Future<int> _refreshJobLinesClient({
    required String clockNo,
    required String periodKey,
    required WorkReportSettings settings,
    required Employee subject,
    required Employee actor,
  }) async {
    await ensurePeriodHeader(
      clockNo: clockNo,
      periodKey: periodKey,
      subject: subject,
      actor: actor,
      settings: settings,
    );

    final bounds = _periodBounds(periodKey, settings);
    final periodStart = bounds['start'] as DateTime;
    final periodEnd = bounds['end'] as DateTime;
    final jobs = await fetchCandidateJobCards(clockNo);
    final included = jobs
        .where((j) => j.id != null)
        .where((j) => WorkReportInclusion.includeJob(
              j,
              clockNo,
              periodStart,
              periodEnd,
              settings.inclusionRules,
            ))
        .toList();

    final existingSnap = await _db
        .collection(Collections.workReportJobLines)
        .where('clockNo', isEqualTo: clockNo)
        .where('periodKey', isEqualTo: periodKey)
        .get();
    final existingByJobId = {
      for (final d in existingSnap.docs)
        d.data()['jobCardId'] as String: d.id,
    };
    final includedIds = included.map((j) => j.id!).toSet();
    final jobsById = {for (final j in included) j.id!: j};

    var added = 0;
    for (final job in included) {
      if (existingByJobId.containsKey(job.id)) continue;
      final lineId = _uuid.v4();
      final line = WorkReportJobLine(
        id: lineId,
        clockNo: clockNo,
        periodKey: periodKey,
        jobCardId: job.id!,
        jobCardNumber: job.jobCardNumber ?? 0,
        correctiveActionSnapshot: job.correctiveAction,
        jobMeta: WorkReportJobMeta.fromJobCard(job),
        workDate: WorkReportJobLine.defaultWorkDateFromJob(job),
      );
      await _writeDoc(
        collection: Collections.workReportJobLines,
        docId: lineId,
        operation: 'set',
        data: line.toFirestore(),
      );
      added++;
    }

    // Backfill workDate on existing lines that never had one (from job create date).
    for (final doc in existingSnap.docs) {
      final data = doc.data();
      if (data['workDate'] != null) continue;
      final jobId = data['jobCardId'] as String? ?? '';
      final job = jobsById[jobId];
      if (job == null) continue;
      await _writeDoc(
        collection: Collections.workReportJobLines,
        docId: doc.id,
        operation: 'update',
        data: {
          'workDate': Timestamp.fromDate(
            WorkReportJobLine.defaultWorkDateFromJob(job),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        merge: true,
      );
    }

    for (final doc in existingSnap.docs) {
      final jobId = doc.data()['jobCardId'] as String? ?? '';
      final orphan = !includedIds.contains(jobId);
      if (orphan && doc.data()['orphan'] != true) {
        await _writeDoc(
          collection: Collections.workReportJobLines,
          docId: doc.id,
          operation: 'update',
          data: {'orphan': true, 'updatedAt': FieldValue.serverTimestamp()},
          merge: true,
        );
      } else if (!orphan && doc.data()['orphan'] == true) {
        await _writeDoc(
          collection: Collections.workReportJobLines,
          docId: doc.id,
          operation: 'update',
          data: {'orphan': false, 'updatedAt': FieldValue.serverTimestamp()},
          merge: true,
        );
      }
    }

    final periodId = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    await _writeDoc(
      collection: Collections.workReportPeriods,
      docId: periodId,
      operation: 'set',
      data: {
        'jobLinesRefreshedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByClockNo': actor.clockNo,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
      merge: true,
    );

    await _recomputePeriodTotals(clockNo, periodKey, actor.clockNo);
    return added;
  }

  /// Admin + post-PDF worker edits for PDF footnote.
  Future<int> countEditsAfterPdf({
    required String clockNo,
    required String periodKey,
    required DateTime pdfGeneratedAt,
  }) async {
    final snap = await _db
        .collection(Collections.workReportAudit)
        .where('clockNo', isEqualTo: clockNo)
        .where('periodKey', isEqualTo: periodKey)
        .get();
    var count = 0;
    for (final doc in snap.docs) {
      final editedAt = doc.data()['editedAt'];
      DateTime? dt;
      if (editedAt is Timestamp) dt = editedAt.toDate();
      if (dt != null && dt.isAfter(pdfGeneratedAt)) count++;
    }
    return count;
  }

  Future<bool> _periodHasPdf(String clockNo, String periodKey) async {
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    final snap =
        await _db.collection(Collections.workReportPeriods).doc(id).get();
    return snap.data()?['pdfGeneratedAt'] != null;
  }

  Future<void> upsertJobLine({
    required WorkReportJobLine line,
    required Employee actor,
    Employee? subjectEmployee,
    bool isAdminEdit = false,
    String? previousHours,
    String? previousSummary,
    String? previousWorkDate,
    WorkReportSettings? settings,
  }) async {
    if (line.hours < 0) {
      throw WorkReportValidationException('Hours cannot be negative');
    }
    if (line.workDate == null) {
      throw WorkReportValidationException('Work date is required');
    }
    final data = line.toFirestore();
    await _writeDoc(
      collection: Collections.workReportJobLines,
      docId: line.id,
      operation: 'set',
      data: data,
      merge: true,
    );

    final s = settings ?? WorkReportSettings.defaults;
    final isPast = WorkReportPeriodUtils.isPastPeriod(
      line.periodKey,
      periodMode: s.defaultPeriodMode,
      periodStartDay: s.periodStartDay,
    );
    // Always audit past-period edits, admin edits, and post-PDF edits.
    final shouldAudit = isPast ||
        (isAdminEdit && isAdmin(actor)) ||
        await _periodHasPdf(line.clockNo, line.periodKey);
    if (shouldAudit) {
      if (previousHours != null && previousHours != line.hours.toString()) {
        await _writeAudit(
          targetCollection: Collections.workReportJobLines,
          targetId: line.id,
          clockNo: line.clockNo,
          periodKey: line.periodKey,
          field: isPast ? 'hours (past period)' : 'hours',
          oldValue: previousHours,
          newValue: line.hours.toString(),
          actor: actor,
        );
      }
      if (previousSummary != null && previousSummary != line.billingSummary) {
        await _writeAudit(
          targetCollection: Collections.workReportJobLines,
          targetId: line.id,
          clockNo: line.clockNo,
          periodKey: line.periodKey,
          field: isPast ? 'billingSummary (past period)' : 'billingSummary',
          oldValue: previousSummary,
          newValue: line.billingSummary,
          actor: actor,
        );
      }
      final newDateStr = line.workDate != null
          ? WorkReportJobLine.dateOnly(line.workDate!).toIso8601String()
          : '';
      if (previousWorkDate != null && previousWorkDate != newDateStr) {
        await _writeAudit(
          targetCollection: Collections.workReportJobLines,
          targetId: line.id,
          clockNo: line.clockNo,
          periodKey: line.periodKey,
          field: isPast ? 'workDate (past period)' : 'workDate',
          oldValue: previousWorkDate,
          newValue: newDateStr,
          actor: actor,
        );
      }
    }
    await _recomputePeriodTotals(
      line.clockNo,
      line.periodKey,
      actor.clockNo,
    );
  }

  Future<void> recordPdfGenerated({
    required String clockNo,
    required String periodKey,
    required Employee actor,
  }) async {
    final online = await ConnectivityService().isOnline();
    if (!online) {
      throw WorkReportValidationException(
        'Connect to the network to record PDF generation',
      );
    }
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    // Atomic version bump — never queue FieldValue.increment offline.
    await _db.collection(Collections.workReportPeriods).doc(id).set({
      'pdfGeneratedAt': FieldValue.serverTimestamp(),
      'pdfVersion': FieldValue.increment(1),
      'lastUpdatedByClockNo': actor.clockNo,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Cap applies to job-line hours summed by timesheet [workDate].
  void validateDailyHoursCap({
    required List<WorkReportJobLine> jobLines,
    required WorkReportSettings settings,
  }) {
    final byDay = <String, double>{};
    for (final line in jobLines) {
      final wd = line.workDate;
      if (wd == null) continue;
      final key = '${wd.year}-${wd.month}-${wd.day}';
      byDay[key] = (byDay[key] ?? 0) + line.hours;
    }
    for (final entry in byDay.entries) {
      if (entry.value > settings.maxHoursPerDay + 0.001) {
        throw WorkReportValidationException(
          'Hours on ${entry.key} exceed ${settings.maxHoursPerDay}h '
          '(${entry.value.toStringAsFixed(1)}h)',
        );
      }
    }
  }

  /// Soft guidance: total hours vs max/day × weekdays in period (week or month).
  String? monthlyHoursSoftWarning({
    required double totalHours,
    required String periodKey,
    required WorkReportSettings settings,
  }) {
    final days = WorkReportPeriodUtils.workingDaysInPeriod(
      periodKey,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    if (days <= 0) return null;
    final softCap = settings.maxHoursPerDay * days;
    if (totalHours > softCap + 0.001) {
      final unit = WorkReportPeriodUtils.isWeekKey(periodKey) ? 'week' : 'period';
      return 'Total ${totalHours.toStringAsFixed(1)}h exceeds rough $unit cap '
          '(${softCap.toStringAsFixed(0)}h = ${settings.maxHoursPerDay}h × $days weekdays). '
          'Review before sharing with Accounts.';
    }
    return null;
  }

  Future<void> recomputePeriodTotalsFromLists({
    required String clockNo,
    required String periodKey,
    required String actorClockNo,
    required List<WorkReportJobLine> jobLines,
  }) async {
    final jobHours = jobLines.fold<double>(0, (s, l) => s + l.hours);
    await _writePeriodTotals(
      clockNo,
      periodKey,
      actorClockNo,
      jobHours,
    );
  }

  Future<void> _recomputePeriodTotals(
    String clockNo,
    String periodKey,
    String actorClockNo,
  ) async {
    final online = await ConnectivityService().isOnline();
    if (!online) {
      // Offline: avoid clobbering totals with incomplete server reads.
      // Next online write or CF trigger will recompute.
      debugPrint('Work report totals skip recompute while offline');
      return;
    }

    try {
      final jobSnap = await _db
          .collection(Collections.workReportJobLines)
          .where('clockNo', isEqualTo: clockNo)
          .where('periodKey', isEqualTo: periodKey)
          .get();

      final jobHours = jobSnap.docs.fold<double>(
        0,
        (total, d) => total + ((d.data()['hours'] as num?)?.toDouble() ?? 0),
      );

      await _writePeriodTotals(
        clockNo,
        periodKey,
        actorClockNo,
        jobHours,
      );
    } catch (e) {
      debugPrint('Work report totals recompute failed: $e');
    }
  }

  Future<void> _writePeriodTotals(
    String clockNo,
    String periodKey,
    String actorClockNo,
    double jobHours,
  ) async {
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    await _writeDoc(
      collection: Collections.workReportPeriods,
      docId: id,
      operation: 'set',
      data: {
        'totalJobHours': jobHours,
        'totalAdditionalHours': 0,
        'totalHours': jobHours,
        'lastUpdatedByClockNo': actorClockNo,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
      merge: true,
    );
  }

  Future<void> _writeAudit({
    required String targetCollection,
    required String targetId,
    required String clockNo,
    required String periodKey,
    required String field,
    required String oldValue,
    required String newValue,
    required Employee actor,
  }) async {
    final payload = {
      'targetCollection': targetCollection,
      'targetId': targetId,
      'clockNo': clockNo,
      'periodKey': periodKey,
      'field': field,
      'oldValue': oldValue,
      'newValue': newValue,
      'editedByClockNo': actor.clockNo,
      'editedByName': actor.name,
      'editedAt': FieldValue.serverTimestamp(),
    };
    final online = await ConnectivityService().isOnline();
    if (!online) {
      // Audit requires admin create in rules for pure clients — workers may fail
      // offline. Queue best-effort; server may reject non-admin. Prefer online.
      final auditId = _uuid.v4();
      await SyncService().addToQueue(
        collection: Collections.workReportAudit,
        operation: 'set',
        data: SyncService.sanitizeForHive(payload),
        documentId: auditId,
      );
      return;
    }
    try {
      await _db.collection(Collections.workReportAudit).add(payload);
    } catch (e) {
      // Workers cannot create audit under tightened rules — CF/trigger owns post-PDF.
      debugPrint('Work report audit write skipped: $e');
    }
  }

  Future<void> _writeDoc({
    required String collection,
    required String docId,
    required String operation,
    required Map<String, dynamic> data,
    bool merge = false,
  }) async {
    final online = await ConnectivityService().isOnline();
    final payload = Map<String, dynamic>.from(data);

    // FieldValue.increment cannot be queued through Hive sanitisation safely.
    if (!online) {
      final hasServerFieldValue = payload.values.any(
        (v) => v is FieldValue,
      );
      if (hasServerFieldValue) {
        // Replace increment with deferred online-only path: store without version
        // bump fields that need server ops; merge safe keys only.
        payload.removeWhere((_, v) => v is FieldValue);
      }
      await SyncService().addToQueue(
        collection: collection,
        operation: operation,
        data: SyncService.sanitizeForHive(payload),
        documentId: docId,
      );
      return;
    }

    if (operation == 'delete') {
      await SyncService().addToQueue(
        collection: collection,
        operation: operation,
        data: {},
        documentId: docId,
      );
      try {
        await _applyDirect(collection, docId, operation, payload, merge);
      } catch (e) {
        debugPrint('Work report delete direct failed, queued: $e');
      }
      return;
    }

    await _applyDirect(collection, docId, operation, payload, merge);
  }

  Future<void> _applyDirect(
    String collection,
    String docId,
    String operation,
    Map<String, dynamic> data,
    bool merge,
  ) async {
    final ref = _db.collection(collection).doc(docId);
    if (operation == 'delete') {
      await ref.delete();
    } else if (operation == 'update' || merge) {
      await ref.set(data, SetOptions(merge: true));
    } else {
      await ref.set(data);
    }
  }
}

class WorkReportValidationException implements Exception {
  WorkReportValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}
