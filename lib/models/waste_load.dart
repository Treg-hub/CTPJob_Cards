import 'package:cloud_firestore/cloud_firestore.dart';

/// Status values for a Waste Load.
enum WasteLoadStatus {
  draft('draft'),
  completed('completed'),
  // Two-phase handoff statuses (manager schedules → guard collects → manager weighbridges)
  scheduled('scheduled'),
  pendingWeighbridge('pending_weighbridge'),
  cancelled('cancelled');

  const WasteLoadStatus(this.value);
  final String value;

  static WasteLoadStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'completed':
        return WasteLoadStatus.completed;
      case 'scheduled':
        return WasteLoadStatus.scheduled;
      case 'pending_weighbridge':
        return WasteLoadStatus.pendingWeighbridge;
      case 'cancelled':
        return WasteLoadStatus.cancelled;
      case 'draft':
      default:
        return WasteLoadStatus.draft;
    }
  }

  String get displayLabel {
    switch (this) {
      case WasteLoadStatus.draft:            return 'Draft';
      case WasteLoadStatus.completed:        return 'Completed';
      case WasteLoadStatus.scheduled:        return 'Scheduled';
      case WasteLoadStatus.pendingWeighbridge: return 'Pending Weighbridge';
      case WasteLoadStatus.cancelled:        return 'Cancelled';
    }
  }
}

/// Core Waste Load document (waste_loads collection).
/// One load = one main waste type + any number of its subtypes (as WasteItems).
class WasteLoad {
  final String? id;
  final String loadNumber;
  final String mainWasteType;
  final DateTime dateTime;
  final String contractorId;
  final String? contractorName;
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
  final List<String> loadPhotos;
  final String? createdBy;
  final String? completedBy;
  final DateTime? completedAt;
  final bool isDeleted;
  final double recordedWeightKg;

  // ── Two-phase handoff fields ──────────────────────────────────────────────
  /// When the contractor is expected (set by manager at scheduling time).
  final DateTime? scheduledFor;
  /// clockNo of the manager who scheduled the load.
  final String? scheduledBy;
  /// Display name of the manager who scheduled the load.
  final String? scheduledByName;
  /// Optional notes from the manager for the guard (e.g. "approx 500kg, heavy vehicle").
  final String? scheduledNotes;
  /// When the guard submitted the collection (transitions to pending_weighbridge).
  final DateTime? pendingWeighbridgeAt;
  /// clockNo of the guard who collected (filled on submitCollection).
  final String? collectedBy;
  final String? collectedByName;
  /// IDs of waste_stock items the manager pre-linked at scheduling time.
  /// Used by WasteBeginCollectionScreen to pre-populate the item list.
  /// Stock items are only marked loaded when the guard confirms collection.
  final List<String> selectedStockIds;

  const WasteLoad({
    this.id,
    required this.loadNumber,
    required this.mainWasteType,
    required this.dateTime,
    required this.contractorId,
    this.contractorName,
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
    this.scheduledFor,
    this.scheduledBy,
    this.scheduledByName,
    this.scheduledNotes,
    this.pendingWeighbridgeAt,
    this.collectedBy,
    this.collectedByName,
    this.selectedStockIds = const [],
  });

  factory WasteLoad.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WasteLoad(
      id: doc.id,
      loadNumber: data['load_number'] as String? ?? '',
      mainWasteType: data['main_waste_type'] as String? ?? '',
      dateTime: (data['date_time'] as Timestamp?)?.toDate()
          ?? (data['createdAt'] as Timestamp?)?.toDate()
          ?? DateTime.now(),
      contractorId: data['contractor_id'] as String? ?? '',
      contractorName: data['contractor_name'] as String?,
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
      scheduledFor: (data['scheduled_for'] as Timestamp?)?.toDate(),
      scheduledBy: data['scheduled_by'] as String?,
      scheduledByName: data['scheduled_by_name'] as String?,
      scheduledNotes: data['scheduled_notes'] as String?,
      pendingWeighbridgeAt: (data['pending_weighbridge_at'] as Timestamp?)?.toDate(),
      collectedBy: data['collected_by'] as String?,
      collectedByName: data['collected_by_name'] as String?,
      selectedStockIds: (data['selected_stock_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'load_number': loadNumber,
      'main_waste_type': mainWasteType,
      'date_time': Timestamp.fromDate(dateTime),
      'contractor_id': contractorId,
      if (contractorName != null) 'contractor_name': contractorName,
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
      if (scheduledFor != null) 'scheduled_for': Timestamp.fromDate(scheduledFor!),
      if (scheduledBy != null) 'scheduled_by': scheduledBy,
      if (scheduledByName != null) 'scheduled_by_name': scheduledByName,
      if (scheduledNotes != null) 'scheduled_notes': scheduledNotes,
      if (pendingWeighbridgeAt != null) 'pending_weighbridge_at': Timestamp.fromDate(pendingWeighbridgeAt!),
      if (collectedBy != null) 'collected_by': collectedBy,
      if (collectedByName != null) 'collected_by_name': collectedByName,
      if (selectedStockIds.isNotEmpty) 'selected_stock_ids': selectedStockIds,
    };
  }

  WasteLoad copyWith({
    String? id,
    String? loadNumber,
    String? mainWasteType,
    DateTime? dateTime,
    String? contractorId,
    String? contractorName,
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
    DateTime? scheduledFor,
    String? scheduledBy,
    String? scheduledByName,
    String? scheduledNotes,
    DateTime? pendingWeighbridgeAt,
    String? collectedBy,
    String? collectedByName,
    List<String>? selectedStockIds,
  }) {
    return WasteLoad(
      id: id ?? this.id,
      loadNumber: loadNumber ?? this.loadNumber,
      mainWasteType: mainWasteType ?? this.mainWasteType,
      dateTime: dateTime ?? this.dateTime,
      contractorId: contractorId ?? this.contractorId,
      contractorName: contractorName ?? this.contractorName,
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
      scheduledFor: scheduledFor ?? this.scheduledFor,
      scheduledBy: scheduledBy ?? this.scheduledBy,
      scheduledByName: scheduledByName ?? this.scheduledByName,
      scheduledNotes: scheduledNotes ?? this.scheduledNotes,
      pendingWeighbridgeAt: pendingWeighbridgeAt ?? this.pendingWeighbridgeAt,
      collectedBy: collectedBy ?? this.collectedBy,
      collectedByName: collectedByName ?? this.collectedByName,
      selectedStockIds: selectedStockIds ?? this.selectedStockIds,
    );
  }
}
