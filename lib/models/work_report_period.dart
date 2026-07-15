import 'package:cloud_firestore/cloud_firestore.dart';

class WorkReportPeriod {
  final String id;
  final String clockNo;
  final String periodKey;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String employeeName;
  final String department;
  final String position;
  final double totalJobHours;
  final double totalAdditionalHours;
  final double totalHours;
  final DateTime? pdfGeneratedAt;
  final int pdfVersion;
  final DateTime? lastUpdatedAt;
  final String lastUpdatedByClockNo;
  final DateTime? jobLinesRefreshedAt;
  /// Free-text notes for the period (shown on PDF Notes section).
  final String notes;

  const WorkReportPeriod({
    required this.id,
    required this.clockNo,
    required this.periodKey,
    required this.periodStart,
    required this.periodEnd,
    this.employeeName = '',
    this.department = '',
    this.position = '',
    this.totalJobHours = 0,
    this.totalAdditionalHours = 0,
    this.totalHours = 0,
    this.pdfGeneratedAt,
    this.pdfVersion = 0,
    this.lastUpdatedAt,
    this.lastUpdatedByClockNo = '',
    this.jobLinesRefreshedAt,
    this.notes = '',
  });

  bool get hasPdf => pdfGeneratedAt != null;

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory WorkReportPeriod.fromFirestore(String id, Map<String, dynamic> data) {
    return WorkReportPeriod(
      id: id,
      clockNo: data['clockNo'] as String? ?? '',
      periodKey: data['periodKey'] as String? ?? '',
      periodStart: _ts(data['periodStart']) ?? DateTime.now(),
      periodEnd: _ts(data['periodEnd']) ?? DateTime.now(),
      employeeName: data['employeeName'] as String? ?? '',
      department: data['department'] as String? ?? '',
      position: data['position'] as String? ?? '',
      totalJobHours: (data['totalJobHours'] as num?)?.toDouble() ?? 0,
      totalAdditionalHours:
          (data['totalAdditionalHours'] as num?)?.toDouble() ?? 0,
      totalHours: (data['totalHours'] as num?)?.toDouble() ?? 0,
      pdfGeneratedAt: _ts(data['pdfGeneratedAt']),
      pdfVersion: data['pdfVersion'] as int? ?? 0,
      lastUpdatedAt: _ts(data['lastUpdatedAt']),
      lastUpdatedByClockNo: data['lastUpdatedByClockNo'] as String? ?? '',
      jobLinesRefreshedAt: _ts(data['jobLinesRefreshedAt']),
      notes: data['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'clockNo': clockNo,
        'periodKey': periodKey,
        'periodStart': Timestamp.fromDate(periodStart),
        'periodEnd': Timestamp.fromDate(periodEnd),
        'employeeName': employeeName,
        'department': department,
        'position': position,
        'totalJobHours': totalJobHours,
        'totalAdditionalHours': totalAdditionalHours,
        'totalHours': totalHours,
        'notes': notes,
        if (pdfGeneratedAt != null)
          'pdfGeneratedAt': Timestamp.fromDate(pdfGeneratedAt!),
        'pdfVersion': pdfVersion,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByClockNo': lastUpdatedByClockNo,
        if (jobLinesRefreshedAt != null)
          'jobLinesRefreshedAt': Timestamp.fromDate(jobLinesRefreshedAt!),
      };
}