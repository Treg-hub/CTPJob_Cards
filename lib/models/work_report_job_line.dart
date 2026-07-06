import 'package:cloud_firestore/cloud_firestore.dart';
import 'job_card.dart';

class WorkReportJobMeta {
  final String type;
  final String department;
  final String area;
  final String machine;
  final String part;

  const WorkReportJobMeta({
    this.type = '',
    this.department = '',
    this.area = '',
    this.machine = '',
    this.part = '',
  });

  factory WorkReportJobMeta.fromJobCard(JobCard job) => WorkReportJobMeta(
        type: job.type.displayName,
        department: job.department,
        area: job.area,
        machine: job.machine,
        part: job.part,
      );

  factory WorkReportJobMeta.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const WorkReportJobMeta();
    return WorkReportJobMeta(
      type: data['type'] as String? ?? '',
      department: data['department'] as String? ?? '',
      area: data['area'] as String? ?? '',
      machine: data['machine'] as String? ?? '',
      part: data['part'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'department': department,
        'area': area,
        'machine': machine,
        'part': part,
      };

  String get locationLabel {
    final parts = [department, area, machine, part]
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return parts.join(' / ');
  }
}

class WorkReportJobLine {
  final String id;
  final String clockNo;
  final String periodKey;
  final String jobCardId;
  final int jobCardNumber;
  final double hours;
  final String billingSummary;
  final String correctiveActionSnapshot;
  final WorkReportJobMeta jobMeta;
  final bool orphan;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkReportJobLine({
    required this.id,
    required this.clockNo,
    required this.periodKey,
    required this.jobCardId,
    this.jobCardNumber = 0,
    this.hours = 0,
    this.billingSummary = '',
    this.correctiveActionSnapshot = '',
    this.jobMeta = const WorkReportJobMeta(),
    this.orphan = false,
    this.createdAt,
    this.updatedAt,
  });

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory WorkReportJobLine.fromFirestore(String id, Map<String, dynamic> data) {
    return WorkReportJobLine(
      id: id,
      clockNo: data['clockNo'] as String? ?? '',
      periodKey: data['periodKey'] as String? ?? '',
      jobCardId: data['jobCardId'] as String? ?? '',
      jobCardNumber: data['jobCardNumber'] as int? ?? 0,
      hours: (data['hours'] as num?)?.toDouble() ?? 0,
      billingSummary: data['billingSummary'] as String? ?? '',
      correctiveActionSnapshot:
          data['correctiveActionSnapshot'] as String? ?? '',
      jobMeta: WorkReportJobMeta.fromMap(
        data['jobMeta'] as Map<String, dynamic>?,
      ),
      orphan: data['orphan'] as bool? ?? false,
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'clockNo': clockNo,
        'periodKey': periodKey,
        'jobCardId': jobCardId,
        'jobCardNumber': jobCardNumber,
        'hours': hours,
        'billingSummary': billingSummary,
        'correctiveActionSnapshot': correctiveActionSnapshot,
        'jobMeta': jobMeta.toFirestore(),
        'orphan': orphan,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}