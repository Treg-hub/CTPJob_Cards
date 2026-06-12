import 'package:cloud_firestore/cloud_firestore.dart';

/// A comment added to a work record by a mechanic, admin, or cost manager.
class FleetWorkComment {
  final String? id;
  final String text;
  final String authorName;
  final String authorClockNo;
  final DateTime createdAt;

  const FleetWorkComment({
    this.id,
    required this.text,
    required this.authorName,
    required this.authorClockNo,
    required this.createdAt,
  });

  factory FleetWorkComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetWorkComment(
      id: doc.id,
      text: data['text'] as String? ?? '',
      authorName: data['author_name'] as String? ?? '',
      authorClockNo: data['author_clock_no'] as String? ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'author_name': authorName,
      'author_clock_no': authorClockNo,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
