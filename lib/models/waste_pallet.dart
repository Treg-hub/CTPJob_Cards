import 'package:cloud_firestore/cloud_firestore.dart';

enum WastePalletStatus {
  onSite('on_site'),
  loaded('loaded'),
  disposed('disposed');

  const WastePalletStatus(this.value);
  final String value;

  static WastePalletStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'loaded':
        return WastePalletStatus.loaded;
      case 'disposed':
        return WastePalletStatus.disposed;
      case 'on_site':
      default:
        return WastePalletStatus.onSite;
    }
  }

  String get displayLabel {
    switch (this) {
      case WastePalletStatus.onSite:    return 'On Site';
      case WastePalletStatus.loaded:    return 'Loaded';
      case WastePalletStatus.disposed:  return 'Disposed';
    }
  }
}

/// A single pallet of waste recorded before a load is planned.
/// Pallets accumulate on-site (status = onSite) until a manager links
/// them to a scheduled load via markPalletsLoaded (status = loaded).
class WastePallet {
  final String? id;
  final String wasteType;
  final String subtype;
  final List<String> photos;
  final double? estimatedWeightKg;
  final WastePalletStatus status;
  final String? loadId;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final bool isDeleted;

  const WastePallet({
    this.id,
    required this.wasteType,
    required this.subtype,
    this.photos = const [],
    this.estimatedWeightKg,
    this.status = WastePalletStatus.onSite,
    this.loadId,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.isDeleted = false,
  });

  factory WastePallet.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WastePallet(
      id: doc.id,
      wasteType: data['waste_type'] as String? ?? '',
      subtype: data['subtype'] as String? ?? '',
      photos: (data['photos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      estimatedWeightKg: (data['estimated_weight_kg'] as num?)?.toDouble(),
      status: WastePalletStatus.fromString(data['status'] as String?),
      loadId: data['load_id'] as String?,
      createdBy: data['created_by'] as String? ?? '',
      createdByName: data['created_by_name'] as String? ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
      notes: data['notes'] as String?,
      isDeleted: data['is_deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'waste_type': wasteType,
      'subtype': subtype,
      'photos': photos,
      if (estimatedWeightKg != null) 'estimated_weight_kg': estimatedWeightKg,
      'status': status.value,
      if (loadId != null) 'load_id': loadId,
      'created_by': createdBy,
      'created_by_name': createdByName,
      if (notes != null) 'notes': notes,
      'is_deleted': isDeleted,
    };
  }

  WastePallet copyWith({
    String? id,
    String? wasteType,
    String? subtype,
    List<String>? photos,
    double? estimatedWeightKg,
    WastePalletStatus? status,
    String? loadId,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    bool? isDeleted,
  }) {
    return WastePallet(
      id: id ?? this.id,
      wasteType: wasteType ?? this.wasteType,
      subtype: subtype ?? this.subtype,
      photos: photos ?? this.photos,
      estimatedWeightKg: estimatedWeightKg ?? this.estimatedWeightKg,
      status: status ?? this.status,
      loadId: loadId ?? this.loadId,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
