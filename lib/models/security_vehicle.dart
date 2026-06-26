import 'package:cloud_firestore/cloud_firestore.dart';

/// Company car / known vehicle in security_vehicles registry.
class SecurityVehicle {
  final String id;
  final String vehicleReg;
  final String? description;
  final String? vehicleType;
  final String? contractorId;
  final String? notes;
  final bool active;
  final DateTime? licenceExpiry;
  final DateTime? complianceExpiry;
  final String? assignedDriver;
  final double? odometerLast;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SecurityVehicle({
    required this.id,
    required this.vehicleReg,
    this.description,
    this.vehicleType,
    this.contractorId,
    this.notes,
    this.active = true,
    this.licenceExpiry,
    this.complianceExpiry,
    this.assignedDriver,
    this.odometerLast,
    this.createdAt,
    this.updatedAt,
  });

  bool get isCompanyCar =>
      (vehicleType ?? '').toLowerCase() == 'company_car';

  static String normalizeReg(String? reg) {
    if (reg == null) return '';
    return reg.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  factory SecurityVehicle.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityVehicle(
      id: doc.id,
      vehicleReg: normalizeReg(data['vehicle_reg'] as String?),
      description: data['description'] as String?,
      vehicleType: data['vehicle_type'] as String?,
      contractorId: data['contractor_id'] as String?,
      notes: data['notes'] as String?,
      active: data['active'] as bool? ?? true,
      licenceExpiry: _toDate(data['licence_expiry']),
      complianceExpiry: _toDate(data['compliance_expiry']),
      assignedDriver: data['assigned_driver'] as String?,
      odometerLast: (data['odometer_last'] as num?)?.toDouble(),
      createdAt: _toDate(data['created_at'] ?? data['createdAt']),
      updatedAt: _toDate(data['updated_at'] ?? data['updatedAt']),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic> toFirestore() => {
        'vehicle_reg': vehicleReg,
        if (description != null) 'description': description,
        if (vehicleType != null) 'vehicle_type': vehicleType,
        if (contractorId != null) 'contractor_id': contractorId,
        if (notes != null) 'notes': notes,
        'active': active,
        if (licenceExpiry != null)
          'licence_expiry': Timestamp.fromDate(licenceExpiry!),
        if (complianceExpiry != null)
          'compliance_expiry': Timestamp.fromDate(complianceExpiry!),
        if (assignedDriver != null) 'assigned_driver': assignedDriver,
        if (odometerLast != null) 'odometer_last': odometerLast,
      };
}