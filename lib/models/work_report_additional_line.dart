import 'package:cloud_firestore/cloud_firestore.dart';

class WorkReportAdditionalLine {
  final String id;
  final String clockNo;
  final String periodKey;
  final DateTime workDate;
  final double hours;
  final String description;
  final int? linkedJobCardNumber;
  final String createdByClockNo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkReportAdditionalLine({
    required this.id,
    required this.clockNo,
    required this.periodKey,
    required this.workDate,
    required this.hours,
    required this.description,
    this.linkedJobCardNumber,
    this.createdByClockNo = '',
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

  factory WorkReportAdditionalLine.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return WorkReportAdditionalLine(
      id: id,
      clockNo: data['clockNo'] as String? ?? '',
      periodKey: data['periodKey'] as String? ?? '',
      workDate: _ts(data['workDate']) ?? DateTime.now(),
      hours: (data['hours'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String? ?? '',
      linkedJobCardNumber: data['linkedJobCardNumber'] as int?,
      createdByClockNo: data['createdByClockNo'] as String? ?? '',
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore({bool isCreate = false}) => {
        'clockNo': clockNo,
        'periodKey': periodKey,
        'workDate': Timestamp.fromDate(
          DateTime(workDate.year, workDate.month, workDate.day),
        ),
        'hours': hours,
        'description': description,
        if (linkedJobCardNumber != null)
          'linkedJobCardNumber': linkedJobCardNumber,
        'createdByClockNo': createdByClockNo,
        if (isCreate) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}