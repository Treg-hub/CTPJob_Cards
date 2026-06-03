import 'package:cloud_firestore/cloud_firestore.dart';

/// A configurable asset type or work type (stored in fleet_types).
/// kind == 'asset_type'  → e.g. "Forklift", "Grab"
/// kind == 'work_type'   → e.g. "Routine", "Repair", "Overhaul", "Inspection"
class FleetType {
  final String? id;
  final String kind; // 'asset_type' | 'work_type'
  final String label;
  final bool active;
  final int sortOrder;
  final DateTime? createdAt;

  const FleetType({
    this.id,
    required this.kind,
    required this.label,
    this.active = true,
    this.sortOrder = 0,
    this.createdAt,
  });

  factory FleetType.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetType(
      id: doc.id,
      kind: data['kind'] as String? ?? 'work_type',
      label: data['label'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      sortOrder: data['sort_order'] as int? ?? 0,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'kind': kind,
      'label': label,
      'active': active,
      'sort_order': sortOrder,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  FleetType copyWith({
    String? id,
    String? kind,
    String? label,
    bool? active,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return FleetType(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      active: active ?? this.active,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
