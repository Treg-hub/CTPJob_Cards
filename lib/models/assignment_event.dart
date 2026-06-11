import 'package:cloud_firestore/cloud_firestore.dart';

class AssignmentEvent {
  final String assignedByName;
  final String assignedByClockNo;
  final List<String> assigneeClockNos;
  final List<String> assigneeNames;
  final DateTime timestamp;
  final bool isUnassign; // true for unassign events
  // Optional type-change marker. When non-null, this entry records a job type
  // change rather than an assignment — the assignee lists are typically empty
  // and the by-fields identify who made the change.
  final String? typeChangedFrom;
  final String? typeChangedTo;

  const AssignmentEvent({
    required this.assignedByName,
    required this.assignedByClockNo,
    required this.assigneeClockNos,
    required this.assigneeNames,
    required this.timestamp,
    this.isUnassign = false,
    this.typeChangedFrom,
    this.typeChangedTo,
  });

  bool get isTypeChange => typeChangedFrom != null && typeChangedTo != null;

  factory AssignmentEvent.fromFirestore(Map<String, dynamic> data) {
    final event = tryFromFirestore(data);
    if (event == null) {
      throw const FormatException('Unparseable AssignmentEvent');
    }
    return event;
  }

  /// Tolerant parser. Returns null only when no usable timestamp can be
  /// recovered. Accepts:
  ///  - the canonical shape (`timestamp` as Timestamp),
  ///  - offline-replay damage (`timestamp` as ISO-8601 string),
  ///  - the legacy Cloud Function auto-assign shape
  ///    (`{clockNo, name, assignedAt, assignedBy, assignedByName}`).
  /// A strict cast here used to throw and poison the whole JobCard parse.
  static AssignmentEvent? tryFromFirestore(Map<String, dynamic> data) {
    final timestamp =
        _parseTimestamp(data['timestamp']) ?? _parseTimestamp(data['assignedAt']);
    if (timestamp == null) return null;

    // Legacy CF auto-assign shape: single assignee under clockNo/name.
    final legacyClockNo = data['clockNo'];
    final legacyName = data['name'];

    return AssignmentEvent(
      assignedByName:
          data['assignedByName'] as String? ?? data['assignedBy'] as String? ?? '',
      assignedByClockNo:
          data['assignedByClockNo'] as String? ?? data['assignedBy'] as String? ?? '',
      assigneeClockNos: _parseStringList(data['assigneeClockNos']) ??
          (legacyClockNo != null ? [legacyClockNo.toString()] : const []),
      assigneeNames: _parseStringList(data['assigneeNames']) ??
          (legacyName != null ? [legacyName.toString()] : const []),
      timestamp: timestamp,
      isUnassign: data['isUnassign'] as bool? ?? false,
      typeChangedFrom: data['typeChangedFrom'] as String?,
      typeChangedTo: data['typeChangedTo'] as String?,
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<String>? _parseStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return null;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'assignedByName': assignedByName,
      'assignedByClockNo': assignedByClockNo,
      'assigneeClockNos': assigneeClockNos,
      'assigneeNames': assigneeNames,
      'timestamp': Timestamp.fromDate(timestamp),
      'isUnassign': isUnassign,
      if (typeChangedFrom != null) 'typeChangedFrom': typeChangedFrom,
      if (typeChangedTo != null) 'typeChangedTo': typeChangedTo,
    };
  }
}