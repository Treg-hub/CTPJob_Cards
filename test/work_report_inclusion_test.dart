import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/assignment_event.dart';
import 'package:ctp_job_cards/models/job_card.dart';
import 'package:ctp_job_cards/models/work_report_settings.dart';
import 'package:ctp_job_cards/utils/work_report_inclusion.dart';
import 'package:ctp_job_cards/utils/work_report_period_utils.dart';

JobCard _job({
  List<String>? assignedClockNos,
  List<AssignmentEvent>? assignmentHistory,
  DateTime? startedAt,
  DateTime? completedAt,
  String? operatorClockNo,
  List<Map<String, dynamic>>? commentsLog,
}) {
  return JobCard(
    id: 'j1',
    department: 'Pre Press',
    area: 'A',
    machine: 'M',
    part: 'P',
    description: 'Test',
    type: JobType.mechanical,
    priority: 3,
    operator: 'Op',
    operatorClockNo: operatorClockNo ?? '99',
    status: JobStatus.inProgress,
    assignedClockNos: assignedClockNos,
    assignmentHistory: assignmentHistory ?? const <AssignmentEvent>[],
    startedAt: startedAt,
    completedAt: completedAt,
    commentsLog: commentsLog ?? const [],
  );
}

void main() {
  const rules = WorkReportInclusionRules();
  const clock = '10338';

  test('includes assigned job with activity in period', () {
    final periodKey = '2026-07';
    final start = WorkReportPeriodUtils.periodStart(periodKey);
    final job = _job(
      assignedClockNos: [clock],
      startedAt: start.add(const Duration(days: 2)),
    );
    expect(
      WorkReportInclusion.includeJob(
        job,
        clock,
        start,
        WorkReportPeriodUtils.periodEnd(periodKey),
        rules,
      ),
      isTrue,
    );
  });

  test('includes started-by history event', () {
    final periodKey = '2026-07';
    final start = WorkReportPeriodUtils.periodStart(periodKey);
    final ts = start.add(const Duration(days: 1));
    final job = _job(
      assignmentHistory: [
        AssignmentEvent(
          assignedByName: 'Started by Test User',
          assignedByClockNo: clock,
          assigneeClockNos: const [],
          assigneeNames: const [],
          timestamp: ts,
        ),
      ],
      startedAt: ts,
    );
    expect(
      WorkReportInclusion.includeJob(
        job,
        clock,
        start,
        WorkReportPeriodUtils.periodEnd(periodKey),
        rules,
      ),
      isTrue,
    );
  });

  test('excludes job with no activity in period', () {
    final periodKey = '2026-07';
    final start = WorkReportPeriodUtils.periodStart(periodKey);
    final job = _job(
      assignedClockNos: [clock],
      startedAt: DateTime(2025, 1, 5),
    );
    expect(
      WorkReportInclusion.includeJob(
        job,
        clock,
        start,
        WorkReportPeriodUtils.periodEnd(periodKey),
        rules,
      ),
      isFalse,
    );
  });

  test('parseLogAt accepts Timestamp and ISO string', () {
    final ts = Timestamp.fromDate(DateTime(2026, 7, 10, 12));
    expect(WorkReportInclusion.parseLogAt(ts), DateTime(2026, 7, 10, 12));
    expect(
      WorkReportInclusion.parseLogAt('2026-07-10T08:00:00.000'),
      isNotNull,
    );
  });

  test('comment activity uses Timestamp at field', () {
    final periodKey = '2026-07';
    final start = WorkReportPeriodUtils.periodStart(periodKey);
    final at = start.add(const Duration(days: 3));
    final job = _job(
      assignedClockNos: const [],
      operatorClockNo: 'other',
      commentsLog: [
        {
          'byClockNo': clock,
          'at': Timestamp.fromDate(at),
          'text': 'note',
        },
      ],
    );
    // commented_by off by default — enable for this case
    const withComments = WorkReportInclusionRules(includeIfCommentedBy: true);
    expect(
      WorkReportInclusion.includeJob(
        job,
        clock,
        start,
        WorkReportPeriodUtils.periodEnd(periodKey),
        withComments,
      ),
      isTrue,
    );
  });

  test('includes operator-created job with created activity via startedAt', () {
    final periodKey = '2026-07';
    final start = WorkReportPeriodUtils.periodStart(periodKey);
    final job = _job(
      assignedClockNos: const [],
      operatorClockNo: clock,
      startedAt: start.add(const Duration(days: 1)),
    );
    expect(
      WorkReportInclusion.includeJob(
        job,
        clock,
        start,
        WorkReportPeriodUtils.periodEnd(periodKey),
        rules,
      ),
      isTrue,
    );
  });
}
