import 'package:cloud_firestore/cloud_firestore.dart';

import 'security_vehicle.dart';

enum SecurityDirection {
  in_,
  out;

  String get value => this == SecurityDirection.in_ ? 'in' : 'out';

  String get label => this == SecurityDirection.in_ ? 'In' : 'Out';

  static SecurityDirection? fromString(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v == 'in') return SecurityDirection.in_;
    if (v == 'out') return SecurityDirection.out;
    return null;
  }
}

enum SecurityEntryType {
  visitor,
  contractor,
  transporter,
  companyCar,
  onFootVisitor;

  String get value {
    switch (this) {
      case SecurityEntryType.visitor:
        return 'visitor';
      case SecurityEntryType.contractor:
        return 'contractor';
      case SecurityEntryType.transporter:
        return 'transporter';
      case SecurityEntryType.companyCar:
        return 'company_car';
      case SecurityEntryType.onFootVisitor:
        return 'on_foot_visitor';
    }
  }

  String get label {
    switch (this) {
      case SecurityEntryType.visitor:
        return 'Visitor';
      case SecurityEntryType.contractor:
        return 'Contractor';
      case SecurityEntryType.transporter:
        return 'Transporter';
      case SecurityEntryType.companyCar:
        return 'Company Car';
      case SecurityEntryType.onFootVisitor:
        return 'On-Foot Visitor';
    }
  }

  static SecurityEntryType? fromString(String? raw) {
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case 'visitor':
        return SecurityEntryType.visitor;
      case 'contractor':
        return SecurityEntryType.contractor;
      case 'transporter':
        return SecurityEntryType.transporter;
      case 'company_car':
        return SecurityEntryType.companyCar;
      case 'on_foot_visitor':
        return SecurityEntryType.onFootVisitor;
      default:
        return null;
    }
  }
}

/// Gate log entry in security_entries.
class SecurityEntry {
  final String id;
  final String? entryNumber;
  final String gateId;
  final String? gateName;
  final SecurityDirection direction;
  final SecurityEntryType? entryType;
  final DateTime? loggedAt;
  final String? vehicleReg;
  final String? vehicleMake;
  final String? vehicleColour;
  final String? driverName;
  final String? visitorName;
  final String? hostName;
  final String? companyName;
  final String? contractorId;
  final String? contractorName;
  final String? purpose;
  final String? destinationAddress;
  final String? employeeClockNo;
  final String? employeeName;
  final bool denyBlocked;
  final String? denyReason;
  final List<String> photos;
  final String? sessionId;
  final String? loggedByClockNo;
  final String? loggedByName;
  final String? loggedByUid;
  final String? clientRef;
  final bool idScanCaptured;
  final bool discScanCaptured;
  final bool driverLicenceScanCaptured;
  final String? driverIdNumber;
  final int? occupantCount;
  // Generic "occupants observed at this direction-event" field — used for
  // visitor-exit ("leaving now" vs recorded on entry) AND for company-car
  // returns ("returning now" vs recorded on the matching exit). Not
  // restricted to literal "leaving" despite the name.
  final int? occupantsLeaving;
  final bool occupantDiscrepancy;
  final String? occupantDiscrepancyNote;
  final bool partialOccupantExit;
  final int? occupantsRemaining;
  final bool discScanMissingFlag;
  final bool driverLicenceMissingFlag;
  final DateTime? discExpiry;
  final DateTime? idExpiry;
  final DateTime? driverLicenceExpiry;
  final bool? transporterCompliant;
  final String? complianceNotes;
  final String? overrideReason;
  final double? odometerStart;
  final double? odometerEnd;
  final double? mileageKm;
  final DateTime? createdAt;

  const SecurityEntry({
    required this.id,
    this.entryNumber,
    required this.gateId,
    this.gateName,
    this.direction = SecurityDirection.in_,
    this.entryType,
    this.loggedAt,
    this.vehicleReg,
    this.vehicleMake,
    this.vehicleColour,
    this.driverName,
    this.visitorName,
    this.hostName,
    this.companyName,
    this.contractorId,
    this.contractorName,
    this.purpose,
    this.destinationAddress,
    this.employeeClockNo,
    this.employeeName,
    this.denyBlocked = false,
    this.denyReason,
    this.photos = const [],
    this.sessionId,
    this.loggedByClockNo,
    this.loggedByName,
    this.loggedByUid,
    this.clientRef,
    this.idScanCaptured = false,
    this.discScanCaptured = false,
    this.driverLicenceScanCaptured = false,
    this.driverIdNumber,
    this.occupantCount,
    this.occupantsLeaving,
    this.occupantDiscrepancy = false,
    this.occupantDiscrepancyNote,
    this.partialOccupantExit = false,
    this.occupantsRemaining,
    this.discScanMissingFlag = false,
    this.driverLicenceMissingFlag = false,
    this.discExpiry,
    this.idExpiry,
    this.driverLicenceExpiry,
    this.transporterCompliant,
    this.complianceNotes,
    this.overrideReason,
    this.odometerStart,
    this.odometerEnd,
    this.mileageKm,
    this.createdAt,
  });

  String get displayPerson =>
      visitorName ?? driverName ?? employeeName ?? '—';

  String get displayReg => vehicleReg ?? '—';

  factory SecurityEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityEntry(
      id: doc.id,
      entryNumber: data['entry_number'] as String?,
      gateId: data['gate_id'] as String? ?? '',
      gateName: data['gate_name'] as String?,
      direction: SecurityDirection.fromString(data['direction'] as String?) ??
          SecurityDirection.in_,
      entryType:
          SecurityEntryType.fromString(data['entry_type'] as String?),
      loggedAt: _toDate(data['logged_at'] ?? data['createdAt']),
      vehicleReg: data['vehicle_reg'] != null
          ? SecurityVehicle.normalizeReg(data['vehicle_reg'] as String?)
          : null,
      vehicleMake: data['vehicle_make'] as String?,
      vehicleColour: data['vehicle_colour'] as String?,
      driverName: data['driver_name'] as String?,
      visitorName: data['visitor_name'] as String?,
      hostName: data['host_name'] as String?,
      companyName: data['company_name'] as String?,
      contractorId: data['contractor_id'] as String?,
      contractorName: data['contractor_name'] as String?,
      purpose: data['purpose'] as String?,
      destinationAddress: data['destination_address'] as String?,
      employeeClockNo: data['employee_clock_no'] as String?,
      employeeName: data['employee_name'] as String?,
      denyBlocked: data['deny_blocked'] as bool? ?? false,
      denyReason: data['deny_reason'] as String?,
      photos: (data['photos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sessionId: data['session_id'] as String?,
      loggedByClockNo: data['logged_by_clock_no'] as String?,
      loggedByName: data['logged_by_name'] as String?,
      loggedByUid: data['logged_by_uid'] as String?,
      clientRef: data['client_ref'] as String?,
      idScanCaptured: data['id_scan_captured'] as bool? ?? false,
      discScanCaptured: data['disc_scan_captured'] as bool? ?? false,
      driverLicenceScanCaptured:
          data['driver_licence_scan_captured'] as bool? ?? false,
      driverIdNumber: data['driver_id_number'] as String?,
      occupantCount: (data['occupant_count'] as num?)?.toInt(),
      occupantsLeaving: (data['occupants_leaving'] as num?)?.toInt(),
      occupantDiscrepancy: data['occupant_discrepancy'] as bool? ?? false,
      occupantDiscrepancyNote: data['occupant_discrepancy_note'] as String?,
      partialOccupantExit: data['partial_occupant_exit'] as bool? ?? false,
      occupantsRemaining: (data['occupants_remaining'] as num?)?.toInt(),
      discScanMissingFlag: data['disc_scan_missing_flag'] as bool? ?? false,
      driverLicenceMissingFlag:
          data['driver_licence_missing_flag'] as bool? ?? false,
      discExpiry: _toDate(data['disc_expiry']),
      idExpiry: _toDate(data['id_expiry']),
      driverLicenceExpiry: _toDate(data['driver_licence_expiry']),
      transporterCompliant: data['transporter_compliant'] as bool?,
      complianceNotes: data['compliance_notes'] as String?,
      overrideReason: data['override_reason'] as String?,
      odometerStart: (data['odometer_start'] as num?)?.toDouble(),
      odometerEnd: (data['odometer_end'] as num?)?.toDouble(),
      mileageKm: (data['mileage_km'] as num?)?.toDouble(),
      createdAt: _toDate(data['createdAt']),
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
        if (entryNumber != null) 'entry_number': entryNumber,
        'gate_id': gateId,
        if (gateName != null) 'gate_name': gateName,
        'direction': direction.value,
        if (entryType != null) 'entry_type': entryType!.value,
        'logged_at': loggedAt != null
            ? Timestamp.fromDate(loggedAt!)
            : FieldValue.serverTimestamp(),
        if (vehicleReg != null) 'vehicle_reg': vehicleReg,
        if (vehicleMake != null) 'vehicle_make': vehicleMake,
        if (vehicleColour != null) 'vehicle_colour': vehicleColour,
        if (driverName != null) 'driver_name': driverName,
        if (visitorName != null) 'visitor_name': visitorName,
        if (hostName != null) 'host_name': hostName,
        if (companyName != null) 'company_name': companyName,
        if (contractorId != null) 'contractor_id': contractorId,
        if (contractorName != null) 'contractor_name': contractorName,
        if (purpose != null) 'purpose': purpose,
        if (destinationAddress != null)
          'destination_address': destinationAddress,
        if (employeeClockNo != null) 'employee_clock_no': employeeClockNo,
        if (employeeName != null) 'employee_name': employeeName,
        'deny_blocked': denyBlocked,
        if (denyReason != null) 'deny_reason': denyReason,
        if (photos.isNotEmpty) 'photos': photos,
        if (sessionId != null) 'session_id': sessionId,
        if (loggedByClockNo != null) 'logged_by_clock_no': loggedByClockNo,
        if (loggedByName != null) 'logged_by_name': loggedByName,
        if (loggedByUid != null) 'logged_by_uid': loggedByUid,
        if (clientRef != null) 'client_ref': clientRef,
        'id_scan_captured': idScanCaptured,
        'disc_scan_captured': discScanCaptured,
        'driver_licence_scan_captured': driverLicenceScanCaptured,
        if (driverIdNumber != null) 'driver_id_number': driverIdNumber,
        if (occupantCount != null) 'occupant_count': occupantCount,
        if (occupantsLeaving != null) 'occupants_leaving': occupantsLeaving,
        'occupant_discrepancy': occupantDiscrepancy,
        if (occupantDiscrepancyNote != null)
          'occupant_discrepancy_note': occupantDiscrepancyNote,
        'partial_occupant_exit': partialOccupantExit,
        if (occupantsRemaining != null)
          'occupants_remaining': occupantsRemaining,
        'disc_scan_missing_flag': discScanMissingFlag,
        'driver_licence_missing_flag': driverLicenceMissingFlag,
        if (discExpiry != null)
          'disc_expiry': Timestamp.fromDate(discExpiry!),
        if (idExpiry != null) 'id_expiry': Timestamp.fromDate(idExpiry!),
        if (driverLicenceExpiry != null)
          'driver_licence_expiry': Timestamp.fromDate(driverLicenceExpiry!),
        if (transporterCompliant != null)
          'transporter_compliant': transporterCompliant,
        if (complianceNotes != null) 'compliance_notes': complianceNotes,
        if (overrideReason != null) 'override_reason': overrideReason,
        if (odometerStart != null) 'odometer_start': odometerStart,
        if (odometerEnd != null) 'odometer_end': odometerEnd,
        if (mileageKm != null) 'mileage_km': mileageKm,
      };
}