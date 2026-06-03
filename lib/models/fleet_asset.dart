import 'package:cloud_firestore/cloud_firestore.dart';

/// Registered machine in the fleet (forklift or grab, or any future asset type).
class FleetAsset {
  final String? id;
  final String typeId;
  final String typeName;
  final String name;
  final String assetTag;
  final String? serial;
  final bool active;
  final double? currentMachineHours;
  final bool hasOpenOosIssue;
  final DateTime? createdAt;

  const FleetAsset({
    this.id,
    required this.typeId,
    required this.typeName,
    required this.name,
    required this.assetTag,
    this.serial,
    this.active = true,
    this.currentMachineHours,
    this.hasOpenOosIssue = false,
    this.createdAt,
  });

  factory FleetAsset.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetAsset(
      id: doc.id,
      typeId: data['type_id'] as String? ?? '',
      typeName: data['type_name'] as String? ?? '',
      name: data['name'] as String? ?? '',
      assetTag: data['asset_tag'] as String? ?? '',
      serial: data['serial'] as String?,
      active: data['active'] as bool? ?? true,
      currentMachineHours: (data['current_machine_hours'] as num?)?.toDouble(),
      hasOpenOosIssue: data['has_open_oos_issue'] as bool? ?? false,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type_id': typeId,
      'type_name': typeName,
      'name': name,
      'asset_tag': assetTag,
      if (serial != null) 'serial': serial,
      'active': active,
      if (currentMachineHours != null) 'current_machine_hours': currentMachineHours,
      'has_open_oos_issue': hasOpenOosIssue,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  FleetAsset copyWith({
    String? id,
    String? typeId,
    String? typeName,
    String? name,
    String? assetTag,
    String? serial,
    bool? active,
    double? currentMachineHours,
    bool? hasOpenOosIssue,
    DateTime? createdAt,
  }) {
    return FleetAsset(
      id: id ?? this.id,
      typeId: typeId ?? this.typeId,
      typeName: typeName ?? this.typeName,
      name: name ?? this.name,
      assetTag: assetTag ?? this.assetTag,
      serial: serial ?? this.serial,
      active: active ?? this.active,
      currentMachineHours: currentMachineHours ?? this.currentMachineHours,
      hasOpenOosIssue: hasOpenOosIssue ?? this.hasOpenOosIssue,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
