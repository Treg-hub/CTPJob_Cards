import 'package:cloud_firestore/cloud_firestore.dart';
import 'assignment_event.dart';

enum JobType {
  mechanical('Mechanical'),
  electrical('Electrical'),
  mechanicalElectrical('Mech/Elec ?'),
  maintenance('Maintenance');

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
  completed('Completed'),
  monitoring('Monitoring'),
  closed('Closed');

  const JobStatus(this.displayName);
  final String displayName;
}

class JobCard {
  final String? id;
  final int? jobCardNumber;
  final String department;
  final String area;
  final String machine;
  final String part;
  final JobType type;
  final int priority;
  final String operator;
  final String? operatorClockNo;
  final List<String>? assignedClockNos;
  final List<String>? assignedNames;
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
  final DateTime? notifiedAt2min;
  final DateTime? notifiedAt7min;
  final String? completedBy;
  final DateTime? completedAt;
  final DateTime? monitoringStartedAt;
  final DateTime? closedAt;
  final List<AssignmentEvent> assignmentHistory;
  final List<Map<String, dynamic>> photos;

  const JobCard({
    this.id,
    this.jobCardNumber,
    required this.department,
    required this.area,
    required this.machine,
    required this.part,
    required this.type,
    required this.priority,
    required this.operator,
    this.operatorClockNo,
    this.assignedClockNos,
    this.assignedNames,
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
    this.notifiedAt2min,
    this.notifiedAt7min,
    this.completedBy,
    this.completedAt,
    this.monitoringStartedAt,
    this.closedAt,
    this.assignmentHistory = const [],
    this.photos = const [],
  });

  factory JobCard.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return JobCard(
      id: doc.id,
      jobCardNumber: data['jobCardNumber'] as int?,
      department: data['department'] as String? ?? '',
      area: data['area'] as String? ?? '',
      machine: data['machine'] as String? ?? '',
      part: data['part'] as String? ?? '',
      type: JobType.fromString(data['type'] as String? ?? 'Mechanical'),
      priority: data['priority'] as int? ?? 3,
      operator: data['operator'] as String? ?? '',
      operatorClockNo: data['operatorClockNo'] as String?,
      assignedClockNos: (data['assignedClockNos'] as List<dynamic>?)?.map((e) => e as String).toList(),
      assignedNames: (data['assignedNames'] as List<dynamic>?)?.map((e) => e as String).toList(),
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
      notifiedAt2min: data['notifiedAt2min'] != null
          ? (data['notifiedAt2min'] as Timestamp).toDate()
          : null,
      notifiedAt7min: data['notifiedAt7min'] != null
          ? (data['notifiedAt7min'] as Timestamp).toDate()
          : null,
      completedBy: data['completedBy'] as String?,
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
      monitoringStartedAt: data['monitoringStartedAt'] != null
          ? (data['monitoringStartedAt'] as Timestamp).toDate()
          : null,
      closedAt: data['closedAt'] != null
          ? (data['closedAt'] as Timestamp).toDate()
          : null,
      assignmentHistory: (data['assignmentHistory'] as List?)?.map((m) => AssignmentEvent.fromFirestore(m)).toList() ?? [],
      photos: _parsePhotos(data['photos']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'jobCardNumber': jobCardNumber,
      'department': department,
      'area': area,
      'machine': machine,
      'part': part,
      'type': type.name,
      'priority': priority,
      'operator': operator,
      'operatorClockNo': operatorClockNo,
      'assignedClockNos': assignedClockNos,
      'assignedNames': assignedNames,
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
      'notifiedAt2min': notifiedAt2min != null ? Timestamp.fromDate(notifiedAt2min!) : null,
      'notifiedAt7min': notifiedAt7min != null ? Timestamp.fromDate(notifiedAt7min!) : null,
      'completedBy': completedBy,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'monitoringStartedAt': monitoringStartedAt != null ? Timestamp.fromDate(monitoringStartedAt!) : null,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'assignmentHistory': assignmentHistory.map((e) => e.toFirestore()).toList(),
      'photos': photos,
    };
  }

  JobCard copyWith({
    String? id,
    int? jobCardNumber,
    String? department,
    String? area,
    String? machine,
    String? part,
    JobType? type,
    int? priority,
    String? operator,
    String? operatorClockNo,
    List<String>? assignedClockNos,
    List<String>? assignedNames,
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
    DateTime? notifiedAt2min,
    DateTime? notifiedAt7min,
    String? completedBy,
    DateTime? completedAt,
    DateTime? monitoringStartedAt,
    DateTime? closedAt,
    List<AssignmentEvent>? assignmentHistory,
    List<Map<String, dynamic>>? photos,
  }) {
    return JobCard(
      id: id ?? this.id,
      jobCardNumber: jobCardNumber ?? this.jobCardNumber,
      department: department ?? this.department,
      area: area ?? this.area,
      machine: machine ?? this.machine,
      part: part ?? this.part,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      operator: operator ?? this.operator,
      operatorClockNo: operatorClockNo ?? this.operatorClockNo,
      assignedClockNos: assignedClockNos ?? this.assignedClockNos,
      assignedNames: assignedNames ?? this.assignedNames,
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
      notifiedAt2min: notifiedAt2min ?? this.notifiedAt2min,
      notifiedAt7min: notifiedAt7min ?? this.notifiedAt7min,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
      monitoringStartedAt: monitoringStartedAt ?? this.monitoringStartedAt,
      closedAt: closedAt ?? this.closedAt,
      assignmentHistory: assignmentHistory ?? this.assignmentHistory,
      photos: photos ?? this.photos,
    );
  }

  bool get isAssigned => assignedClockNos?.isNotEmpty ?? false;
  bool get isCompleted => status == JobStatus.completed;

  static List<Map<String, dynamic>> _parsePhotos(dynamic photosData) {
    if (photosData == null) return const [];
    final list = photosData as List;
    return list.map((e) {
      if (e is String) {
        return {
          'section': 'legacy',
          'url': e,
          'addedBy': 'Unknown',
          'timestamp': '',
        };
      } else if (e is Map<String, dynamic>) {
        return e;
      }
      return <String, dynamic>{};
    }).toList();
  }
}

extension JobStatusExtension on JobStatus {
  static JobStatus fromString(String value) {
    return JobStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => JobStatus.open,
    );
  }
}