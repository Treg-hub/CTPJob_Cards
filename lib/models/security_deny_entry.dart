import 'package:cloud_firestore/cloud_firestore.dart';

import 'security_vehicle.dart';

/// Deny-list row from security_deny_list.
class SecurityDenyEntry {
  final String id;
  final String vehicleReg;
  final String? driverName;
  final String reason;
  final String? addedByClockNo;
  final DateTime? addedAt;
  final bool active;
  final String? notes;

  const SecurityDenyEntry({
    required this.id,
    required this.vehicleReg,
    this.driverName,
    required this.reason,
    this.addedByClockNo,
    this.addedAt,
    this.active = true,
    this.notes,
  });

  factory SecurityDenyEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityDenyEntry(
      id: doc.id,
      vehicleReg: SecurityVehicle.normalizeReg(data['vehicle_reg'] as String?),
      driverName: data['driver_name'] as String?,
      reason: data['reason'] as String? ?? '',
      addedByClockNo: data['added_by_clock_no'] as String?,
      addedAt: data['added_at'] is Timestamp
          ? (data['added_at'] as Timestamp).toDate()
          : null,
      active: data['active'] as bool? ?? true,
      notes: data['notes'] as String?,
    );
  }
}