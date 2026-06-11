import 'package:cloud_firestore/cloud_firestore.dart';
import 'assignment_event.dart';

enum JobType {
  mechanical('Mechanical'),
  electrical('Electrical'),
  mechanicalElectrical('Mech/Elec'),
  maintenance('Maintenance'),
  building('Building'),
  specialist('Pre Press Spec');

  const JobType(this.displayName);
  final String displayName;

  /// Parse a stored Firestore string back into a [JobType].
  ///
  /// New writes use [name] (camelCase, e.g. "mechanicalElectrical"), so the
  /// case-sensitive name match is the fast path. Legacy/display-name forms
  /// ("Mech/Elec ?", "Mechanical", etc.) are also accepted so old docs read
  /// correctly without a migration.
  static JobType fromString(String value) {
    for (final t in JobType.values) {
      if (t.name == value) return t;
    }
    final normalized = value.toLowerCase().replaceAll(' ', '').replaceAll('?', '');
    switch (normalized) {
      case 'mechanical':
        return JobType.mechanical;
      case 'electrical':
        return JobType.electrical;
      case 'mech/elec':
      case 'mechelec':
      case 'mechanicalelectrical':
        return JobType.mechanicalElectrical;
      case 'maintenance':
        return JobType.maintenance;
      case 'building':
        return JobType.building;
      case 'specialist':
        return JobType.specialist;
    }
    return JobType.mechanical;
  }
}

enum JobStatus {
  open('Open'),
  inProgress('In Progress'),
  monitor('Monitoring'),
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
  final String correctiveAction;
  final int reoccurrenceCount;
  final JobStatus status;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? lastUpdatedAt;
  final DateTime? notificationReceivedAt;
  final DateTime? notifiedAtStage1;
  final DateTime? notifiedAtStage2;
  final DateTime? notifiedAtStage3;
  final DateTime? notifiedAtStage4;
  final String? completedBy;
  final DateTime? completedAt;
  final DateTime? monitoringStartedAt;
  final DateTime? closedAt;
  final List<AssignmentEvent> assignmentHistory;
  final List<Map<String, dynamic>> photos;
  final Map<String, DateTime> reviewedBy;

  // Structured entries ({text, by, byClockNo, at}) written via arrayUnion by
  // JobCardActionsService. Dual-written alongside the legacy string blobs
  // (comments/notes/correctiveAction) so old app versions still see entries.
  // NOT included in toFirestore — only arrayUnion may touch them, otherwise a
  // stale whole-doc save could erase concurrent entries.
  final List<Map<String, dynamic>> commentsLog;
  final List<Map<String, dynamic>> notesLog;
  final List<Map<String, dynamic>> correctiveActionLog;

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
    this.correctiveAction = '',
    this.reoccurrenceCount = 1,
    this.status = JobStatus.open,
    this.createdAt,
    this.assignedAt,
    this.startedAt,
    this.lastUpdatedAt,
    this.notificationReceivedAt,
    this.notifiedAtStage1,
    this.notifiedAtStage2,
    this.notifiedAtStage3,
    this.notifiedAtStage4,
    this.completedBy,
    this.completedAt,
    this.monitoringStartedAt,
    this.closedAt,
    this.assignmentHistory = const [],
    this.photos = const [],
    this.reviewedBy = const {},
    this.commentsLog = const [],
    this.notesLog = const [],
    this.correctiveActionLog = const [],
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
      assignedClockNos: _parseStringList(data['assignedClockNos']),
      assignedNames: _parseStringList(data['assignedNames']),
      description: data['description'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      comments: data['comments'] as String? ?? '',
      correctiveAction: data['correctiveAction'] as String? ?? '',
      reoccurrenceCount: data['reoccurrenceCount'] as int? ?? 1,
      status: JobStatusExtension.fromString(data['status'] as String? ?? 'Open'),
      createdAt: parseTimestamp(data['createdAt']),
      assignedAt: parseTimestamp(data['assignedAt']),
      startedAt: parseTimestamp(data['startedAt']),
      lastUpdatedAt: parseTimestamp(data['lastUpdatedAt']),
      notificationReceivedAt: parseTimestamp(data['notificationReceivedAt']),
      notifiedAtStage1: parseTimestamp(data['notifiedAtStage1']),
      notifiedAtStage2: parseTimestamp(data['notifiedAtStage2']),
      notifiedAtStage3: parseTimestamp(data['notifiedAtStage3']),
      notifiedAtStage4: parseTimestamp(data['notifiedAtStage4']),
      completedBy: data['completedBy'] as String?,
      completedAt: parseTimestamp(data['completedAt']),
      monitoringStartedAt: parseTimestamp(data['monitoringStartedAt']),
      closedAt: parseTimestamp(data['closedAt']),
      assignmentHistory: _parseAssignmentHistory(data['assignmentHistory']),
      photos: _parsePhotos(data['photos']),
      reviewedBy: _parseReviewedBy(data['reviewedBy']),
      commentsLog: _parseEntryLog(data['commentsLog']),
      notesLog: _parseEntryLog(data['notesLog']),
      correctiveActionLog: _parseEntryLog(data['correctiveActionLog']),
    );
  }

  /// Parses a structured entry log ({text, by, byClockNo, at}) tolerantly.
  static List<Map<String, dynamic>> _parseEntryLog(dynamic value) {
    if (value is! List) return const [];
    final entries = <Map<String, dynamic>>[];
    for (final raw in value) {
      if (raw is Map) entries.add(raw.map((k, v) => MapEntry(k.toString(), v)));
    }
    return entries;
  }

  /// Tolerant timestamp parser. Offline-queue replays historically wrote
  /// ISO-8601 strings into Timestamp fields, and a single bad value used to
  /// make this factory throw — poisoning every job list stream at once.
  /// Accepts [Timestamp], [String] (ISO-8601), [DateTime], or null.
  static DateTime? parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Parses assignmentHistory, skipping entries that can't be understood
  /// (e.g. legacy Cloud-Function-shaped events) instead of throwing.
  static List<AssignmentEvent> _parseAssignmentHistory(dynamic value) {
    if (value is! List) return const [];
    final events = <AssignmentEvent>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final event =
          AssignmentEvent.tryFromFirestore(Map<String, dynamic>.from(raw));
      if (event != null) events.add(event);
    }
    return events;
  }

  /// Serialise to a Firestore map.
  ///
  /// Set [includePhotos] to `false` for routine updates so that a `set(..., merge: true)`
  /// write does not overwrite the `photos` array. Photo writes go through
  /// `FirestoreService.addPhotoToJobCard` / `removePhotoFromJobCard` (arrayUnion/arrayRemove)
  /// to avoid clobbering concurrent additions.
  Map<String, dynamic> toFirestore({bool includePhotos = true}) {
    final map = <String, dynamic>{
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
      'correctiveAction': correctiveAction,
      'reoccurrenceCount': reoccurrenceCount,
      'status': status.name,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'notificationReceivedAt': notificationReceivedAt != null ? Timestamp.fromDate(notificationReceivedAt!) : null,
      'notifiedAtStage1': notifiedAtStage1 != null ? Timestamp.fromDate(notifiedAtStage1!) : null,
      'notifiedAtStage2': notifiedAtStage2 != null ? Timestamp.fromDate(notifiedAtStage2!) : null,
      'notifiedAtStage3': notifiedAtStage3 != null ? Timestamp.fromDate(notifiedAtStage3!) : null,
      'notifiedAtStage4': notifiedAtStage4 != null ? Timestamp.fromDate(notifiedAtStage4!) : null,
      'completedBy': completedBy,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'monitoringStartedAt': monitoringStartedAt != null ? Timestamp.fromDate(monitoringStartedAt!) : null,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'assignmentHistory': assignmentHistory.map((e) => e.toFirestore()).toList(),
    };
    if (includePhotos) map['photos'] = photos;
    return map;
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
    String? correctiveAction,
    int? reoccurrenceCount,
    JobStatus? status,
    DateTime? createdAt,
    DateTime? assignedAt,
    DateTime? startedAt,
    DateTime? lastUpdatedAt,
    DateTime? notificationReceivedAt,
    DateTime? notifiedAtStage1,
    DateTime? notifiedAtStage2,
    DateTime? notifiedAtStage3,
    DateTime? notifiedAtStage4,
    String? completedBy,
    DateTime? completedAt,
    DateTime? monitoringStartedAt,
    DateTime? closedAt,
    List<AssignmentEvent>? assignmentHistory,
    List<Map<String, dynamic>>? photos,
    Map<String, DateTime>? reviewedBy,
    List<Map<String, dynamic>>? commentsLog,
    List<Map<String, dynamic>>? notesLog,
    List<Map<String, dynamic>>? correctiveActionLog,
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
      correctiveAction: correctiveAction ?? this.correctiveAction,
      reoccurrenceCount: reoccurrenceCount ?? this.reoccurrenceCount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      assignedAt: assignedAt ?? this.assignedAt,
      startedAt: startedAt ?? this.startedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      notificationReceivedAt: notificationReceivedAt ?? this.notificationReceivedAt,
      notifiedAtStage1: notifiedAtStage1 ?? this.notifiedAtStage1,
      notifiedAtStage2: notifiedAtStage2 ?? this.notifiedAtStage2,
      notifiedAtStage3: notifiedAtStage3 ?? this.notifiedAtStage3,
      notifiedAtStage4: notifiedAtStage4 ?? this.notifiedAtStage4,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
      monitoringStartedAt: monitoringStartedAt ?? this.monitoringStartedAt,
      closedAt: closedAt ?? this.closedAt,
      assignmentHistory: assignmentHistory ?? this.assignmentHistory,
      photos: photos ?? this.photos,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      commentsLog: commentsLog ?? this.commentsLog,
      notesLog: notesLog ?? this.notesLog,
      correctiveActionLog: correctiveActionLog ?? this.correctiveActionLog,
    );
  }

  bool get isAssigned => assignedClockNos?.isNotEmpty ?? false;
  bool get isClosed => status == JobStatus.closed;

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
      } else if (e is Map) {
        // Accept any Map shape (cloud_firestore may surface Map<Object?, Object?>
        // depending on SDK version) and normalise the keys to String.
        return e.map((k, v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    }).toList();
  }

  static Map<String, DateTime> _parseReviewedBy(dynamic data) {
    if (data == null || data is! Map) return const {};
    final result = <String, DateTime>{};
    final map = data as Map<Object?, Object?>;
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val is Timestamp) {
        result[key] = val.toDate();
      } else if (val is String) {
        final dt = DateTime.tryParse(val);
        if (dt != null) result[key] = dt;
      }
    }
    return result;
  }

  // ==================== NEW HELPER METHOD ====================
  static List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) {
      return value.isEmpty ? [] : [value];
    }
    return null;
  }
}

extension JobStatusExtension on JobStatus {
  static JobStatus fromString(String value) {
    // Legacy Firestore docs stored 'monitor' before the enum was renamed to 'inProgress'+'monitor'
    return JobStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => JobStatus.open,
    );
  }
}