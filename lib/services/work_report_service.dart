import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../models/work_report_additional_line.dart';
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
        .map((snap) => snap.docs
            .map((d) => WorkReportJobLine.fromFirestore(d.id, d.data()))
            .toList()
          ..sort((a, b) => b.jobCardNumber.compareTo(a.jobCardNumber)));
  }

  Stream<List<WorkReportAdditionalLine>> watchAdditionalLines(
    String clockNo,
    String periodKey,
  ) {
    return _db
        .collection(Collections.workReportAdditionalLines)
        .where('clockNo', isEqualTo: clockNo)
        .where('periodKey', isEqualTo: periodKey)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WorkReportAdditionalLine.fromFirestore(d.id, d.data()))
            .toList()
          ..sort((a, b) => b.workDate.compareTo(a.workDate)));
  }

  Future<List<JobCard>> fetchCandidateJobCards(String clockNo) async {
    final snap = await _db
        .collection(Collections.jobCards)
        .where('assignedClockNos', arrayContains: clockNo)
        .get();
    return FirestoreService.parseJobCards(snap.docs);
  }

  Future<void> ensurePeriodHeader({
    required String clockNo,
    required String periodKey,
    required Employee subject,
    required Employee actor,
  }) async {
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    final ref = _db.collection(Collections.workReportPeriods).doc(id);
    final existing = await ref.get();
    if (existing.exists) return;

    final payload = {
      'clockNo': clockNo,
      'periodKey': periodKey,
      'periodStart': Timestamp.fromDate(
        WorkReportPeriodUtils.periodStart(periodKey),
      ),
      'periodEnd': Timestamp.fromDate(
        WorkReportPeriodUtils.periodEnd(periodKey),
      ),
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

  /// Re-runs inclusion; adds new lines; marks stale lines orphan (keeps hours).
  Future<int> refreshJobLines({
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
    );

    final periodStart = WorkReportPeriodUtils.periodStart(periodKey);
    final periodEnd = WorkReportPeriodUtils.periodEnd(periodKey);
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
      );
      await _writeDoc(
        collection: Collections.workReportJobLines,
        docId: lineId,
        operation: 'set',
        data: line.toFirestore(),
      );
      added++;
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

    await _recomputePeriodTotals(clockNo, periodKey, actor.clockNo);
    return added;
  }

  Future<void> upsertJobLine({
    required WorkReportJobLine line,
    required Employee actor,
    Employee? subjectEmployee,
    bool isAdminEdit = false,
    String? previousHours,
    String? previousSummary,
  }) async {
    final data = line.toFirestore();
    await _writeDoc(
      collection: Collections.workReportJobLines,
      docId: line.id,
      operation: 'set',
      data: data,
      merge: true,
    );
    if (isAdminEdit && isAdmin(actor)) {
      if (previousHours != null && previousHours != line.hours.toString()) {
        await _writeAudit(
          targetCollection: Collections.workReportJobLines,
          targetId: line.id,
          clockNo: line.clockNo,
          periodKey: line.periodKey,
          field: 'hours',
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
          field: 'billingSummary',
          oldValue: previousSummary,
          newValue: line.billingSummary,
          actor: actor,
        );
      }
    }
    await _recomputePeriodTotals(line.clockNo, line.periodKey, actor.clockNo);
  }

  Future<void> upsertAdditionalLine({
    required WorkReportAdditionalLine line,
    required Employee actor,
    required WorkReportSettings settings,
    bool isCreate = false,
    bool isAdminEdit = false,
    WorkReportAdditionalLine? previous,
  }) async {
    _validateAdditionalLine(line, settings);
    final data = line.toFirestore(isCreate: isCreate);
    await _writeDoc(
      collection: Collections.workReportAdditionalLines,
      docId: line.id,
      operation: 'set',
      data: data,
      merge: !isCreate,
    );
    if (isAdminEdit && isAdmin(actor) && previous != null) {
      for (final field in ['hours', 'description', 'workDate']) {
        final oldVal = _fieldValue(previous, field);
        final newVal = _fieldValue(line, field);
        if (oldVal != newVal) {
          await _writeAudit(
            targetCollection: Collections.workReportAdditionalLines,
            targetId: line.id,
            clockNo: line.clockNo,
            periodKey: line.periodKey,
            field: field,
            oldValue: oldVal,
            newValue: newVal,
            actor: actor,
          );
        }
      }
    }
    await _recomputePeriodTotals(line.clockNo, line.periodKey, actor.clockNo);
  }

  Future<void> deleteAdditionalLine({
    required WorkReportAdditionalLine line,
    required Employee actor,
  }) async {
    await _writeDoc(
      collection: Collections.workReportAdditionalLines,
      docId: line.id,
      operation: 'delete',
      data: {},
    );
    await _recomputePeriodTotals(line.clockNo, line.periodKey, actor.clockNo);
  }

  Future<void> recordPdfGenerated({
    required String clockNo,
    required String periodKey,
    required Employee actor,
  }) async {
    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    final ref = _db.collection(Collections.workReportPeriods).doc(id);
    final snap = await ref.get();
    final currentVersion =
        (snap.data()?['pdfVersion'] as int?) ?? 0;
    await _writeDoc(
      collection: Collections.workReportPeriods,
      docId: id,
      operation: 'set',
      data: {
        'pdfGeneratedAt': FieldValue.serverTimestamp(),
        'pdfVersion': currentVersion + 1,
        'lastUpdatedByClockNo': actor.clockNo,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
      merge: true,
    );
  }

  void validateDailyHoursCap({
    required List<WorkReportAdditionalLine> additionalLines,
    required WorkReportSettings settings,
  }) {
    final byDay = <String, double>{};
    for (final line in additionalLines) {
      final key =
          '${line.workDate.year}-${line.workDate.month}-${line.workDate.day}';
      byDay[key] = (byDay[key] ?? 0) + line.hours;
    }
    for (final entry in byDay.entries) {
      if (entry.value > settings.maxHoursPerDay + 0.001) {
        throw WorkReportValidationException(
          'Hours on ${entry.key} exceed ${settings.maxHoursPerDay}h limit '
          '(${entry.value.toStringAsFixed(1)}h)',
        );
      }
    }
  }

  Future<void> _recomputePeriodTotals(
    String clockNo,
    String periodKey,
    String actorClockNo,
  ) async {
    final jobSnap = await _db
        .collection(Collections.workReportJobLines)
        .where('clockNo', isEqualTo: clockNo)
        .where('periodKey', isEqualTo: periodKey)
        .get();
    final addSnap = await _db
        .collection(Collections.workReportAdditionalLines)
        .where('clockNo', isEqualTo: clockNo)
        .where('periodKey', isEqualTo: periodKey)
        .get();

    final jobHours = jobSnap.docs.fold<double>(
      0,
      (sum, d) => sum + ((d.data()['hours'] as num?)?.toDouble() ?? 0),
    );
    final addHours = addSnap.docs.fold<double>(
      0,
      (sum, d) => sum + ((d.data()['hours'] as num?)?.toDouble() ?? 0),
    );

    final id = WorkReportPeriodUtils.periodDocId(clockNo, periodKey);
    await _writeDoc(
      collection: Collections.workReportPeriods,
      docId: id,
      operation: 'set',
      data: {
        'totalJobHours': jobHours,
        'totalAdditionalHours': addHours,
        'totalHours': jobHours + addHours,
        'lastUpdatedByClockNo': actorClockNo,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
      merge: true,
    );
  }

  void _validateAdditionalLine(
    WorkReportAdditionalLine line,
    WorkReportSettings settings,
  ) {
    if (line.hours <= 0) {
      throw WorkReportValidationException('Additional work hours must be > 0');
    }
    if (line.description.trim().isEmpty) {
      throw WorkReportValidationException('Description is required');
    }
    if (!WorkReportPeriodUtils.isDateInPeriod(line.workDate, line.periodKey)) {
      throw WorkReportValidationException('Date must fall within the period');
    }
    if (line.hours > settings.maxHoursPerDay) {
      throw WorkReportValidationException(
        'A single entry cannot exceed ${settings.maxHoursPerDay}h',
      );
    }
  }

  String _fieldValue(WorkReportAdditionalLine line, String field) {
    switch (field) {
      case 'hours':
        return line.hours.toString();
      case 'description':
        return line.description;
      case 'workDate':
        return line.workDate.toIso8601String();
      default:
        return '';
    }
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
    await _db.collection(Collections.workReportAudit).add({
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
    });
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

    if (!online || operation == 'delete') {
      await SyncService().addToQueue(
        collection: collection,
        operation: operation,
        data: SyncService.sanitizeForHive(payload),
        documentId: docId,
      );
      if (online && operation != 'delete') {
        try {
          await _applyDirect(collection, docId, operation, payload, merge);
          return;
        } catch (e) {
          debugPrint('Work report direct write failed, queued: $e');
        }
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