import 'package:cloud_firestore/cloud_firestore.dart';

/// Status values for a Waste Load (matches spec).
enum WasteLoadStatus {
  draft('draft'),
  completed('completed');

  const WasteLoadStatus(this.value);
  final String value;

  static WasteLoadStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'completed':
        return WasteLoadStatus.completed;
      case 'draft':
      default:
        return WasteLoadStatus.draft;
    }
  }
}

/// Core Waste Load document (waste_loads collection).
/// One load = one main waste type + any number of its subtypes (as WasteItems).
class WasteLoad {
  final String? id;
  final String loadNumber; // e.g. WT-20260531-001
  final String mainWasteType;
  final DateTime dateTime;
  final String contractorId;
  final String? collectionCompanyId;
  final String driverName;
  final String vehicleReg;
  final String? paperDocumentRef;
  final String? weighbridgeNumber;
  final double? actualWeighbridgeWeightKg;
  final String? weighbridgeTicketPhotoUrl;
  final String? notes;
  final WasteLoadStatus status;
  final String? driverSignatureUrl;
  final List<String> loadPhotos; // optional load-level photos (full truck etc.)
  final String? createdBy;
  final String? completedBy;
  final DateTime? completedAt;
  final bool isDeleted;

  const WasteLoad({
    this.id,
    required this.loadNumber,
    required this.mainWasteType,
    required this.dateTime,
    required this.contractorId,
    this.collectionCompanyId,
    required this.driverName,
    required this.vehicleReg,
    this.paperDocumentRef,
    this.weighbridgeNumber,
    this.actualWeighbridgeWeightKg,
    this.weighbridgeTicketPhotoUrl,
    this.notes,
    this.status = WasteLoadStatus.draft,
    this.driverSignatureUrl,
    this.loadPhotos = const [],
    this.createdBy,
    this.completedBy,
    this.completedAt,
    this.isDeleted = false,
    this.recordedWeightKg = 0.0,
  });

  /// Total weight of all items (calculated at creation time and stored for deviation checks).
  /// Falls back to 0 if not present on the doc (older loads or items not yet summed).
  final double recordedWeightKg;

  factory WasteLoad.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WasteLoad(
      id: doc.id,
      loadNumber: data['load_number'] as String? ?? '',
      mainWasteType: data['main_waste_type'] as String? ?? '',
      dateTime: (data['date_time'] as Timestamp?)?.toDate() ?? DateTime.now(),
      contractorId: data['contractor_id'] as String? ?? '',
      collectionCompanyId: data['collection_company_id'] as String?,
      driverName: data['driver_name'] as String? ?? '',
      vehicleReg: data['vehicle_reg'] as String? ?? '',
      paperDocumentRef: data['paper_document_ref'] as String?,
      weighbridgeNumber: data['weighbridge_number'] as String?,
      actualWeighbridgeWeightKg:
          (data['actual_weighbridge_weight_kg'] as num?)?.toDouble(),
      weighbridgeTicketPhotoUrl: data['weighbridge_ticket_photo_url'] as String?,
      notes: data['notes'] as String?,
      status: WasteLoadStatus.fromString(data['status'] as String?),
      driverSignatureUrl: data['driver_signature_url'] as String?,
      loadPhotos: (data['load_photos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdBy: data['created_by'] as String?,
      completedBy: data['completed_by'] as String?,
      completedAt: (data['completed_at'] as Timestamp?)?.toDate(),
      isDeleted: data['is_deleted'] as bool? ?? false,
      recordedWeightKg: (data['recorded_weight_kg'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'load_number': loadNumber,
      'main_waste_type': mainWasteType,
      'date_time': Timestamp.fromDate(dateTime),
      'contractor_id': contractorId,
      'collection_company_id': collectionCompanyId,
      'driver_name': driverName,
      'vehicle_reg': vehicleReg,
      'paper_document_ref': paperDocumentRef,
      'weighbridge_number': weighbridgeNumber,
      'actual_weighbridge_weight_kg': actualWeighbridgeWeightKg,
      'weighbridge_ticket_photo_url': weighbridgeTicketPhotoUrl,
      'notes': notes,
      'status': status.value,
      'driver_signature_url': driverSignatureUrl,
      'load_photos': loadPhotos,
      'created_by': createdBy,
      'completed_by': completedBy,
      'completed_at':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'is_deleted': isDeleted,
      'recorded_weight_kg': recordedWeightKg,
    };
  }

  WasteLoad copyWith({
    String? id,
    String? loadNumber,
    String? mainWasteType,
    DateTime? dateTime,
    String? contractorId,
    String? collectionCompanyId,
    String? driverName,
    String? vehicleReg,
    String? paperDocumentRef,
    String? weighbridgeNumber,
    double? actualWeighbridgeWeightKg,
    String? weighbridgeTicketPhotoUrl,
    String? notes,
    WasteLoadStatus? status,
    String? driverSignatureUrl,
    List<String>? loadPhotos,
    String? createdBy,
    String? completedBy,
    DateTime? completedAt,
    bool? isDeleted,
    double? recordedWeightKg,
  }) {
    return WasteLoad(
      id: id ?? this.id,
      loadNumber: loadNumber ?? this.loadNumber,
      mainWasteType: mainWasteType ?? this.mainWasteType,
      dateTime: dateTime ?? this.dateTime,
      contractorId: contractorId ?? this.contractorId,
      collectionCompanyId: collectionCompanyId ?? this.collectionCompanyId,
      driverName: driverName ?? this.driverName,
      vehicleReg: vehicleReg ?? this.vehicleReg,
      paperDocumentRef: paperDocumentRef ?? this.paperDocumentRef,
      weighbridgeNumber: weighbridgeNumber ?? this.weighbridgeNumber,
      actualWeighbridgeWeightKg:
          actualWeighbridgeWeightKg ?? this.actualWeighbridgeWeightKg,
      weighbridgeTicketPhotoUrl:
          weighbridgeTicketPhotoUrl ?? this.weighbridgeTicketPhotoUrl,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      driverSignatureUrl: driverSignatureUrl ?? this.driverSignatureUrl,
      loadPhotos: loadPhotos ?? this.loadPhotos,
      createdBy: createdBy ?? this.createdBy,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      recordedWeightKg: recordedWeightKg ?? this.recordedWeightKg,
    );
  }
}
