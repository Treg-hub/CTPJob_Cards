import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job_card.dart';
import '../models/work_report_settings.dart';

/// Client-side job-card inclusion for My Timesheet (tunable via settings).
class WorkReportInclusion {
  WorkReportInclusion._();

  /// Parse log `at` fields — Firestore often yields [Timestamp], offline queue
  /// may yield ISO strings; never require only [DateTime].
  static DateTime? parseLogAt(dynamic at) {
    if (at == null) return null;
    if (at is DateTime) return at;
    if (at is Timestamp) return at.toDate();
    if (at is String) return DateTime.tryParse(at);
    // JobCard.parseTimestamp covers Timestamp/DateTime/String already.
    return JobCard.parseTimestamp(at);
  }

  static bool jobInvolvesWorker(
    JobCard job,
    String clockNo,
    WorkReportInclusionRules rules,
  ) {
    if (rules.includeIfAssigned && _wasAssigned(job, clockNo)) return true;
    if (rules.includeIfStartedBy && _wasStartedBy(job, clockNo)) return true;
    if (rules.includeIfCompletedBy && _wasCompletedBy(job, clockNo)) {
      return true;
    }
    if (rules.includeIfCommentedBy && _hasLogEntry(job.commentsLog, clockNo)) {
      return true;
    }
    if (rules.includeIfNotedBy && _hasLogEntry(job.notesLog, clockNo)) {
      return true;
    }
    // Creator / operator of the card often does the work without staying assigned.
    if (rules.includeIfAssigned && job.operatorClockNo == clockNo) return true;
    return false;
  }

  static bool hasActivityInPeriod(
    JobCard job,
    String clockNo,
    DateTime periodStart,
    DateTime periodEnd,
    WorkReportInclusionRules rules,
  ) {
    if (!rules.requireActivityInPeriod) return true;

    bool inRange(DateTime? dt) {
      if (dt == null) return false;
      return !dt.isBefore(periodStart) && !dt.isAfter(periodEnd);
    }

    if (inRange(job.startedAt)) return true;
    if (inRange(job.completedAt)) return true;
    if (inRange(job.assignedAt)) return true;
    if (inRange(job.createdAt) && job.operatorClockNo == clockNo) return true;

    for (final event in job.assignmentHistory) {
      if (!inRange(event.timestamp)) continue;
      if (event.assigneeClockNos.contains(clockNo) && !event.isUnassign) {
        return true;
      }
      if (event.assignedByClockNo == clockNo) return true;
    }

    for (final entry in [
      ...job.commentsLog,
      ...job.correctiveActionLog,
      ...job.notesLog,
    ]) {
      if (entry['byClockNo']?.toString() != clockNo) continue;
      final dt = parseLogAt(entry['at']);
      if (inRange(dt)) return true;
    }

    return false;
  }

  static bool includeJob(
    JobCard job,
    String clockNo,
    DateTime periodStart,
    DateTime periodEnd,
    WorkReportInclusionRules rules,
  ) {
    if (!jobInvolvesWorker(job, clockNo, rules)) return false;
    return hasActivityInPeriod(
      job,
      clockNo,
      periodStart,
      periodEnd,
      rules,
    );
  }

  static bool _wasAssigned(JobCard job, String clockNo) {
    if (job.assignedClockNos?.contains(clockNo) ?? false) return true;
    for (final event in job.assignmentHistory) {
      if (event.isUnassign) continue;
      if (event.assigneeClockNos.contains(clockNo)) return true;
    }
    return false;
  }

  static bool _wasStartedBy(JobCard job, String clockNo) {
    for (final event in job.assignmentHistory) {
      if (event.assignedByClockNo != clockNo) continue;
      final name = event.assignedByName.toLowerCase();
      if (name.contains('started by') || name.contains('start')) {
        return true;
      }
    }
    return false;
  }

  static bool _wasCompletedBy(JobCard job, String clockNo) {
    for (final event in job.assignmentHistory) {
      if (event.assignedByClockNo != clockNo) continue;
      final name = event.assignedByName.toLowerCase();
      if (name.contains('completed by') ||
          name.contains('monitoring by') ||
          name.contains('complete')) {
        return true;
      }
    }
    if (job.correctiveActionLog.any((e) => e['byClockNo']?.toString() == clockNo)) {
      return true;
    }
    // completedBy may be display name; prefer clock if present on completedBy field.
    if (job.completedBy != null &&
        job.completedBy!.isNotEmpty &&
        job.operatorClockNo == clockNo &&
        job.completedAt != null) {
      // Weak signal only when operator completed their own card.
      return true;
    }
    return false;
  }

  static bool _hasLogEntry(List<Map<String, dynamic>> log, String clockNo) {
    return log.any((e) => e['byClockNo']?.toString() == clockNo);
  }
}
