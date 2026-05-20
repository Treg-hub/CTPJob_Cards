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
    return AssignmentEvent(
      assignedByName: data['assignedByName'] ?? '',
      assignedByClockNo: data['assignedByClockNo'] ?? '',
      assigneeClockNos: List<String>.from(data['assigneeClockNos'] ?? []),
      assigneeNames: List<String>.from(data['assigneeNames'] ?? []),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      isUnassign: data['isUnassign'] as bool? ?? false,
      typeChangedFrom: data['typeChangedFrom'] as String?,
      typeChangedTo: data['typeChangedTo'] as String?,
    );
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