import 'package:cloud_firestore/cloud_firestore.dart';

/// Contractor / supplier from security_contractors.
class SecurityContractor {
  final String id;
  final String name;
  final String? contact;
  final bool active;
  final DateTime? createdAt;

  const SecurityContractor({
    required this.id,
    required this.name,
    this.contact,
    this.active = true,
    this.createdAt,
  });

  factory SecurityContractor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityContractor(
      id: doc.id,
      name: data['name'] as String? ?? '',
      contact: data['contact'] as String?,
      active: data['active'] as bool? ?? true,
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : null,
    );
  }
}