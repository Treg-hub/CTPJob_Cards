import 'package:cloud_firestore/cloud_firestore.dart';

enum JobType {
  mechanical('Mechanical'),
  electrical('Electrical'),
  mechanicalElectrical('Mech/Elec (Unknown)');

  const JobType(this.displayName);
  final String displayName;

  static JobType fromString(String value) {
    return JobType.values.firstWhere(
      (type) => type.name == value.toLowerCase(),
      orElse: () => JobType.mechanical,
    );
  }
}

enum JobStatus {
  open('Open'),
  completed('Completed');

  const JobStatus(this.displayName);
  final String displayName;
}

class JobCard {
  final String? id;
  final String department;
  final String area;
  final String machine;
  final String part;
  final JobType type;
  final int priority;
  final String operator;
  final String? operatorClockNo;
  final String? assignedTo;
  final String? assignedToName;
  final String description;
  final String notes;
  final String comments;
  final int reoccurrenceCount;
  final JobStatus status;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? lastUpdatedAt;
  final DateTime? notificationReceivedAt;
  final String? completedBy;
  final DateTime? completedAt;

  const JobCard({
    this.id,
    required this.department,
    required this.area,
    required this.machine,
    required this.part,
    required this.type,
    required this.priority,
    required this.operator,
    this.operatorClockNo,
    this.assignedTo,
    this.assignedToName,
    required this.description,
    this.notes = '',
    this.comments = '',
    this.reoccurrenceCount = 1,
    this.status = JobStatus.open,
    this.createdAt,
    this.assignedAt,
    this.startedAt,
    this.lastUpdatedAt,
    this.notificationReceivedAt,
    this.completedBy,
    this.completedAt,
  });

  factory JobCard.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return JobCard(
      id: doc.id,
      department: data['department'] as String? ?? '',
      area: data['area'] as String? ?? '',
      machine: data['machine'] as String? ?? '',
      part: data['part'] as String? ?? '',
      type: JobType.fromString(data['type'] as String? ?? 'Mechanical'),
      priority: data['priority'] as int? ?? 3,
      operator: data['operator'] as String? ?? '',
      operatorClockNo: data['operatorClockNo'] as String?,
      assignedTo: data['assignedTo'] as String?,
      assignedToName: data['assignedToName'] as String?,
      description: data['description'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      comments: data['comments'] as String? ?? '',
      reoccurrenceCount: data['reoccurrenceCount'] as int? ?? 1,
      status: JobStatusExtension.fromString(data['status'] as String? ?? 'Open'),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      assignedAt: data['assignedAt'] != null
          ? (data['assignedAt'] as Timestamp).toDate()
          : null,
      startedAt: data['startedAt'] != null
          ? (data['startedAt'] as Timestamp).toDate()
          : null,
      lastUpdatedAt: data['lastUpdatedAt'] != null
          ? (data['lastUpdatedAt'] as Timestamp).toDate()
          : null,
      notificationReceivedAt: data['notificationReceivedAt'] != null
          ? (data['notificationReceivedAt'] as Timestamp).toDate()
          : null,
      completedBy: data['completedBy'] as String?,
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'department': department,
      'area': area,
      'machine': machine,
      'part': part,
      'type': type.name,
      'priority': priority,
      'operator': operator,
      'operatorClockNo': operatorClockNo,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'description': description,
      'notes': notes,
      'comments': comments,
      'reoccurrenceCount': reoccurrenceCount,
      'status': status.name,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'lastUpdatedAt': FieldValue.serverTimestamp(), // Always update on save
      'notificationReceivedAt': notificationReceivedAt != null ? Timestamp.fromDate(notificationReceivedAt!) : null,
      'completedBy': completedBy,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  JobCard copyWith({
    String? id,
    String? department,
    String? area,
    String? machine,
    String? part,
    JobType? type,
    int? priority,
    String? operator,
    String? operatorClockNo,
    String? assignedTo,
    String? assignedToName,
    String? description,
    String? notes,
    String? comments,
    int? reoccurrenceCount,
    JobStatus? status,
    DateTime? createdAt,
    DateTime? assignedAt,
    DateTime? startedAt,
    DateTime? lastUpdatedAt,
    DateTime? notificationReceivedAt,
    String? completedBy,
    DateTime? completedAt,
  }) {
    return JobCard(
      id: id ?? this.id,
      department: department ?? this.department,
      area: area ?? this.area,
      machine: machine ?? this.machine,
      part: part ?? this.part,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      operator: operator ?? this.operator,
      operatorClockNo: operatorClockNo ?? this.operatorClockNo,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      comments: comments ?? this.comments,
      reoccurrenceCount: reoccurrenceCount ?? this.reoccurrenceCount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      assignedAt: assignedAt ?? this.assignedAt,
      startedAt: startedAt ?? this.startedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      notificationReceivedAt: notificationReceivedAt ?? this.notificationReceivedAt,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  bool get isAssigned => assignedTo != null && assignedTo!.isNotEmpty;
  bool get isCompleted => status == JobStatus.completed;
}

extension JobStatusExtension on JobStatus {
  static JobStatus fromString(String value) {
    return JobStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => JobStatus.open,
    );
  }
}