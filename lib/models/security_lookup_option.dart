import 'package:cloud_firestore/cloud_firestore.dart';

/// Suggestion list entry for gate log fields (host, company, department).
class SecurityLookupOption {
  final String id;
  final String type;
  final String value;
  final bool active;

  const SecurityLookupOption({
    required this.id,
    required this.type,
    required this.value,
    this.active = true,
  });

  factory SecurityLookupOption.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityLookupOption(
      id: doc.id,
      type: data['type'] as String? ?? '',
      value: data['value'] as String? ?? '',
      active: data['active'] as bool? ?? true,
    );
  }
}