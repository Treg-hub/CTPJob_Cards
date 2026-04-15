import 'package:cloud_firestore/cloud_firestore.dart';

class AssignmentEvent {
  final String assignedByName;
  final String assignedByClockNo;
  final List<String> assigneeClockNos;
  final List<String> assigneeNames;
  final DateTime timestamp;
  final bool isUnassign; // true for unassign events

  const AssignmentEvent({
    required this.assignedByName,
    required this.assignedByClockNo,
    required this.assigneeClockNos,
    required this.assigneeNames,
    required this.timestamp,
    this.isUnassign = false,
  });

  factory AssignmentEvent.fromFirestore(Map<String, dynamic> data) {
    return AssignmentEvent(
      assignedByName: data['assignedByName'] ?? '',
      assignedByClockNo: data['assignedByClockNo'] ?? '',
      assigneeClockNos: List<String>.from(data['assigneeClockNos'] ?? []),
      assigneeNames: List<String>.from(data['assigneeNames'] ?? []),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      isUnassign: data['isUnassign'] as bool? ?? false,
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
    };
  }
}