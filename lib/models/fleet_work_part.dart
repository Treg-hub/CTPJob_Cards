import 'package:cloud_firestore/cloud_firestore.dart';

/// A single part used in a work record (sub-collection of fleet_work_records).
/// No pricing — costs are entered separately by the cost manager.
class FleetWorkPart {
  final String? id;
  final String partName;
  final int? quantity;
  final DateTime? createdAt;

  const FleetWorkPart({
    this.id,
    required this.partName,
    this.quantity,
    this.createdAt,
  });

  factory FleetWorkPart.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetWorkPart(
      id: doc.id,
      partName: data['part_name'] as String? ?? '',
      quantity: data['quantity'] as int?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'part_name': partName,
      if (quantity != null) 'quantity': quantity,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
