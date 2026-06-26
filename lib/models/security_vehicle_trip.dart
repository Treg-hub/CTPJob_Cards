import 'package:cloud_firestore/cloud_firestore.dart';

import 'security_entry.dart';
import 'security_vehicle.dart' show SecurityVehicle;

/// Denormalised company-car trip line in security_vehicle_trips.
class SecurityVehicleTrip {
  final String id;
  final String vehicleReg;
  final String? gateId;
  final SecurityDirection direction;
  final String? entryId;
  final DateTime? loggedAt;
  final String? driverName;
  final String? contractorId;
  final String? sessionId;
  final double? mileageKm;
  final double? odometerStart;
  final double? odometerEnd;

  const SecurityVehicleTrip({
    required this.id,
    required this.vehicleReg,
    this.gateId,
    this.direction = SecurityDirection.in_,
    this.entryId,
    this.loggedAt,
    this.driverName,
    this.contractorId,
    this.sessionId,
    this.mileageKm,
    this.odometerStart,
    this.odometerEnd,
  });

  double get computedMileage {
    if (mileageKm != null && mileageKm! > 0) return mileageKm!;
    if (odometerStart != null &&
        odometerEnd != null &&
        odometerEnd! > odometerStart!) {
      return odometerEnd! - odometerStart!;
    }
    return 0;
  }

  factory SecurityVehicleTrip.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityVehicleTrip(
      id: doc.id,
      vehicleReg: _normalizeReg(data['vehicle_reg'] as String?),
      gateId: data['gate_id'] as String?,
      direction: SecurityDirection.fromString(data['direction'] as String?) ??
          SecurityDirection.in_,
      entryId: data['entry_id'] as String?,
      loggedAt: _toDate(data['logged_at'] ?? data['createdAt']),
      driverName: data['driver_name'] as String?,
      contractorId: data['contractor_id'] as String?,
      sessionId: data['session_id'] as String?,
      mileageKm: (data['mileage_km'] as num?)?.toDouble(),
      odometerStart: (data['odometer_start'] as num?)?.toDouble(),
      odometerEnd: (data['odometer_end'] as num?)?.toDouble(),
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
        if (gateId != null) 'gate_id': gateId,
        'direction': direction.value,
        if (entryId != null) 'entry_id': entryId,
        'logged_at': loggedAt != null
            ? Timestamp.fromDate(loggedAt!)
            : FieldValue.serverTimestamp(),
        if (driverName != null) 'driver_name': driverName,
        if (contractorId != null) 'contractor_id': contractorId,
        if (sessionId != null) 'session_id': sessionId,
        if (mileageKm != null) 'mileage_km': mileageKm,
        if (odometerStart != null) 'odometer_start': odometerStart,
        if (odometerEnd != null) 'odometer_end': odometerEnd,
      };
}

String _normalizeReg(String? reg) => SecurityVehicle.normalizeReg(reg);