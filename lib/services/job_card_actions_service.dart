import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../constants/collections.dart';
import '../models/assignment_event.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import 'connectivity_service.dart';
import '../utils/persona_audit.dart';

/// Single implementation of every job-card action, shared by the detail
/// screen, the My Work tab, and Daily Review.
///
/// Why this exists (2026-06 review):
///  - Each screen used to build a full JobCard copy and merge-set the WHOLE
///    document from possibly-stale local state — two concurrent editors (or a
///    delayed offline replay) silently erased each other's comments, status
///    changes, and assignments. Every method here issues a FIELD-SCOPED
///    `update` touching only what the action changes, with `arrayUnion` /
///    `arrayRemove` for the shared arrays.
///  - My Work had its own divergent Start/Complete logic (no assignment, no
///    history, notes instead of correctiveAction).
///  - Every write stamps `lastUpdatedBy`/`lastUpdatedByName`, which the
///    server-side `onJobCardWritten` audit trigger records as the actor.
///
/// Offline behaviour: these writes ride Firestore's own offline persistence
/// (enabled in main.dart), which queues `update` + FieldValue sentinels
/// durably across restarts — unlike the Hive queue, whose sanitisation cannot
/// represent arrayUnion and historically corrupted timestamps. When offline,
/// the write is fired without awaiting (the Future only completes on server
/// ack); the local cache reflects it immediately.
class JobCardActionsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String jobCardId) =>
      _firestore.collection(Collections.jobCards).doc(jobCardId);

  Map<String, dynamic> _actorStamp(Employee by) => {
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedBy': by.clockNo,
        'lastUpdatedByName': by.name,
      };

  /// Structured log entry for commentsLog/notesLog/correctiveActionLog.
  /// serverTimestamp sentinels are not allowed inside array elements, so the
  /// entry carries client time plus the author identity.
  Map<String, dynamic> _logEntry(Employee by, String text) => {
        'text': text,
        'by': by.name,
        'byClockNo': by.clockNo,
        'at': Timestamp.fromDate(DateTime.now()),
      };

  /// Legacy string-blob entry, kept in sync (dual-write) so app versions that
  /// only read the string fields still see every comment/note.
  String _legacyEntry(Employee by, String text, {String? prefix}) {
    final now = DateTime.now();
    final stamp =
        '[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}]';
    return '\n\n$stamp ${prefix != null ? '$prefix ' : ''}${by.name}: $text';
  }

  /// Applies [update]. Online: awaited so errors surface to the caller.
  /// Offline: fired unawaited — Firestore persistence queues it durably and
  /// the local cache (which the detail stream reads) applies it immediately;
  /// awaiting would hang the UI until reconnect.
  Future<void> _apply(String jobCardId, Map<String, dynamic> update) async {
    assertPersonaSubmitAllowed();
    final payload = withPersonaAudit(update);
    final ref = _ref(jobCardId);
    final online = kIsWeb || await ConnectivityService().isOnline();
    if (online) {
      await ref.update(payload);
    } else {
      unawaited(ref.update(payload).catchError((Object e) {
        debugPrint('⚠️ Deferred job-card update failed after reconnect: $e');
      }));
      debugPrint('📤 Job-card update queued in Firestore persistence (offline)');
    }
  }

  // ==================== LIFECYCLE ====================

  /// Start (or join) a job: self-assigns the actor if needed and moves the
  /// job to In Progress. Safe under concurrency — two techs starting at once
  /// both land in assignedClockNos.
  Future<void> startJob(JobCard job, Employee by) async {
    final now = DateTime.now();
    final alreadyAssigned = job.assignedClockNos?.contains(by.clockNo) ?? false;

    final events = <Map<String, dynamic>>[];
    if (!alreadyAssigned) {
      events.add(AssignmentEvent(
        assignedByName: by.name,
        assignedByClockNo: by.clockNo,
        assigneeClockNos: [by.clockNo],
        assigneeNames: [by.name],
        timestamp: now,
      ).toFirestore());
    }
    events.add(AssignmentEvent(
      assignedByName: 'Started by ${by.name}',
      assignedByClockNo: by.clockNo,
      assigneeClockNos: const [],
      assigneeNames: const [],
      timestamp: now,
    ).toFirestore());

    await _apply(job.id!, {
      'status': JobStatus.inProgress.name,
      'startedAt': Timestamp.fromDate(now),
      'assignedClockNos': FieldValue.arrayUnion([by.clockNo]),
      'assignedNames': FieldValue.arrayUnion([by.name]),
      if (job.assignedAt == null) 'assignedAt': Timestamp.fromDate(now),
      'assignmentHistory': FieldValue.arrayUnion(events),
      ..._actorStamp(by),
    });
  }

  /// Complete a job (close it) or move it to Monitoring, recording the
  /// corrective action both as a structured log entry and the legacy string.
  Future<void> completeJob(
    JobCard job,
    Employee by,
    String note, {
    required bool withMonitoring,
  }) async {
    final now = DateTime.now();
    final prefix = withMonitoring ? 'Monitoring by' : 'Completed by';
    final event = AssignmentEvent(
      assignedByName: '$prefix ${by.name}',
      assignedByClockNo: by.clockNo,
      assigneeClockNos: const [],
      assigneeNames: const [],
      timestamp: now,
    );

    await _apply(job.id!, {
      'status':
          withMonitoring ? JobStatus.monitor.name : JobStatus.closed.name,
      'completedBy': by.name,
      'completedAt': Timestamp.fromDate(now),
      if (withMonitoring) 'monitoringStartedAt': Timestamp.fromDate(now),
      if (!withMonitoring) 'closedAt': Timestamp.fromDate(now),
      'correctiveAction':
          job.correctiveAction + _legacyEntry(by, note, prefix: '$prefix '),
      'correctiveActionLog': FieldValue.arrayUnion([_logEntry(by, note)]),
      'assignmentHistory': FieldValue.arrayUnion([event.toFirestore()]),
      ..._actorStamp(by),
    });
  }

  /// "Adjustment Made" on a monitoring job: restarts the 7-day window.
  Future<void> adjustmentMade(JobCard job, Employee by, String note) async {
    final now = DateTime.now();
    final event = AssignmentEvent(
      assignedByName: 'Adjustment by ${by.name}',
      assignedByClockNo: by.clockNo,
      assigneeClockNos: const [],
      assigneeNames: const [],
      timestamp: now,
    );
    await _apply(job.id!, {
      'monitoringStartedAt': Timestamp.fromDate(now),
      'correctiveAction': job.correctiveAction +
          _legacyEntry(by, '$note – restarted monitoring',
              prefix: 'Adjustment by '),
      'correctiveActionLog': FieldValue.arrayUnion([_logEntry(by, note)]),
      'assignmentHistory': FieldValue.arrayUnion([event.toFirestore()]),
      ..._actorStamp(by),
    });
  }

  // ==================== ASSIGNMENT ====================

  /// Manager assignment from the Assign sheet. Replacement semantics — the
  /// sheet shows the full desired list (it can remove people too), so the
  /// arrays are set, not unioned. Notification fan-out to newly added
  /// assignees happens server-side (onJobCardAssigned diffs the array).
  Future<void> setAssignees(
    JobCard job,
    Employee by,
    List<String> clockNos,
    List<String> names,
  ) async {
    final now = DateTime.now();
    final event = AssignmentEvent(
      assignedByName: by.name,
      assignedByClockNo: by.clockNo,
      assigneeClockNos: List<String>.from(clockNos),
      assigneeNames: List<String>.from(names),
      timestamp: now,
    );
    await _apply(job.id!, {
      'assignedClockNos': clockNos,
      'assignedNames': names,
      if (job.assignedAt == null) 'assignedAt': Timestamp.fromDate(now),
      'assignmentHistory': FieldValue.arrayUnion([event.toFirestore()]),
      ..._actorStamp(by),
    });
  }

  /// Remove the actor from the job's assignees.
  Future<void> selfUnassign(JobCard job, Employee by) async {
    final event = AssignmentEvent(
      assignedByName: by.name,
      assignedByClockNo: by.clockNo,
      assigneeClockNos: [by.clockNo],
      assigneeNames: [by.name],
      timestamp: DateTime.now(),
      isUnassign: true,
    );
    await _apply(job.id!, {
      'assignedClockNos': FieldValue.arrayRemove([by.clockNo]),
      'assignedNames': FieldValue.arrayRemove([by.name]),
      'assignmentHistory': FieldValue.arrayUnion([event.toFirestore()]),
      ..._actorStamp(by),
    });
  }

  // ==================== COMMENTS / NOTES ====================

  /// Append a comment (operators / managers). Optionally updates the
  /// reoccurrence count captured in the same dialog.
  Future<void> addComment(
    JobCard job,
    Employee by,
    String text, {
    int? reoccurrenceCount,
  }) async {
    await _apply(job.id!, {
      'comments': job.comments + _legacyEntry(by, text),
      'commentsLog': FieldValue.arrayUnion([_logEntry(by, text)]),
      if (reoccurrenceCount != null) 'reoccurrenceCount': reoccurrenceCount,
      ..._actorStamp(by),
    });
  }

  /// Append a technical note (technicians / managers).
  Future<void> addNote(JobCard job, Employee by, String text) async {
    await _apply(job.id!, {
      'notes': job.notes + _legacyEntry(by, text),
      'notesLog': FieldValue.arrayUnion([_logEntry(by, text)]),
      ..._actorStamp(by),
    });
  }

  // ==================== LOCATION ====================

  /// Breadcrumb correction (creator/admin only — enforced by the screen).
  Future<void> editLocation(
    JobCard job,
    Employee by, {
    required String department,
    required String area,
    required String machine,
    required String part,
  }) async {
    await _apply(job.id!, {
      'department': department,
      'area': area,
      'machine': machine,
      'part': part,
      ..._actorStamp(by),
    });
  }
}
