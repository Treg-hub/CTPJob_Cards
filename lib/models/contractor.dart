import 'package:cloud_firestore/cloud_firestore.dart';

/// Waste contractor (waste_contractors collection).
class Contractor {
  final String? id;
  final String name;
  final String? contact;
  final List<String> wasteTypeIds;

  const Contractor({
    this.id,
    required this.name,
    this.contact,
    this.wasteTypeIds = const [],
  });

  factory Contractor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Contractor(
      id: doc.id,
      name: data['name'] as String? ?? '',
      contact: data['contact'] as String?,
      wasteTypeIds: (data['waste_type_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'contact': contact,
        'waste_type_ids': wasteTypeIds,
      };
}
