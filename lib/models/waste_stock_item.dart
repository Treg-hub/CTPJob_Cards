import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a waste stock item before and after it is dispatched on a load.
enum WasteStockStatus {
  onSite('on_site'),
  loaded('loaded'),
  disposed('disposed');

  const WasteStockStatus(this.value);
  final String value;

  static WasteStockStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'loaded':
        return WasteStockStatus.loaded;
      case 'disposed':
        return WasteStockStatus.disposed;
      case 'on_site':
      default:
        return WasteStockStatus.onSite;
    }
  }

  String get displayLabel {
    switch (this) {
      case WasteStockStatus.onSite:    return 'On Site';
      case WasteStockStatus.loaded:    return 'Loaded';
      case WasteStockStatus.disposed:  return 'Disposed';
    }
  }
}

/// A single on-site waste item recorded before a load is planned.
///
/// Stock items accumulate on-site (status = onSite) until a manager links
/// them to a scheduled load via markStockLoaded (status = loaded).
///
/// The [wasteType] field (e.g. "Paper Waste", "Copper Waste") determines
/// which waste module owns the item, making this model extensible to any
/// waste type without schema changes.
class WasteStockItem {
  final String? id;
  final String wasteType;
  final String subtype;
  final List<String> photos;
  final double? estimatedWeightKg;
  final WasteStockStatus status;
  final String? loadId;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final bool isDeleted;

  const WasteStockItem({
    this.id,
    required this.wasteType,
    required this.subtype,
    this.photos = const [],
    this.estimatedWeightKg,
    this.status = WasteStockStatus.onSite,
    this.loadId,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.isDeleted = false,
  });

  static DateTime _parseDate(dynamic value, {DateTime? fallback}) {
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      final parsed = DateTime.tryParse(
        value.length == 10 ? '${value}T00:00:00' : value,
      );
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value == null) return null;
    return _parseDate(value, fallback: DateTime.now());
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool _parseBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return defaultValue;
  }

  factory WasteStockItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WasteStockItem(
      id: doc.id,
      wasteType: (data['waste_type'] ?? data['wasteType'] ?? '') as String,
      subtype: data['subtype'] as String? ?? '',
      photos: (data['photos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((url) => url.isNotEmpty)
              .toList() ??
          const [],
      estimatedWeightKg: _parseDouble(
        data['estimated_weight_kg'] ?? data['estimatedWeightKg'],
      ),
      status: WasteStockStatus.fromString(data['status'] as String?),
      loadId: (data['load_id'] ?? data['loadId']) as String?,
      createdBy: (data['created_by'] ?? data['createdBy'] ?? '') as String,
      createdByName:
          (data['created_by_name'] ?? data['createdByName'] ?? '') as String,
      createdAt: _parseDate(data['created_at'] ?? data['createdAt']),
      updatedAt: _parseOptionalDate(data['updated_at'] ?? data['updatedAt']),
      notes: data['notes'] as String?,
      isDeleted: _parseBool(data['is_deleted'] ?? data['isDeleted']),
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

  WasteStockItem copyWith({
    String? id,
    String? wasteType,
    String? subtype,
    List<String>? photos,
    double? estimatedWeightKg,
    WasteStockStatus? status,
    String? loadId,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    bool? isDeleted,
  }) {
    return WasteStockItem(
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
