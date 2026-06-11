import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String clockNo;
  final String name;
  final String position;
  final String department;
  final String? fcmToken;
  final bool isOnSite;
  final bool isAdmin;
  final DateTime? fcmTokenUpdatedAt;

  /// Bumped server-side when this employee's custom auth claims are minted or
  /// changed (Phase 3 RBAC). Clients watch it and force an ID-token refresh.
  /// Read-only on the client: intentionally NOT written by toFirestore so an
  /// employee update can never clobber it.
  final int? claimsVersion;

  const Employee({
    required this.clockNo,
    required this.name,
    required this.position,
    required this.department,
    this.fcmToken,
    this.isOnSite = true,
    this.isAdmin = false,
    this.fcmTokenUpdatedAt,
    this.claimsVersion,
  });

  String get displayName => '$name ($clockNo) - $position';

  factory Employee.fromFirestore(Map<String, dynamic> data, String clockNo) {
    return Employee(
      clockNo: clockNo,
      name: data['name'] as String? ?? '',
      position: data['position'] as String? ?? '',
      department: data['department'] as String? ?? '',
      fcmToken: data['fcmToken'] as String?,
      isOnSite: data['isOnSite'] as bool? ?? true,
      isAdmin: data['isAdmin'] as bool? ?? false,
      fcmTokenUpdatedAt: data['fcmTokenUpdatedAt'] != null
          ? (data['fcmTokenUpdatedAt'] as Timestamp).toDate()
          : null,
      claimsVersion: data['claimsVersion'] as int?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clockNo': clockNo,
      'name': name,
      'position': position,
      'department': department,
      'fcmToken': fcmToken,
      'isOnSite': isOnSite,
      'isAdmin': isAdmin,
      'fcmTokenUpdatedAt': fcmTokenUpdatedAt != null
          ? Timestamp.fromDate(fcmTokenUpdatedAt!)
          : null,
    };
  }

  Employee copyWith({
    String? clockNo,
    String? name,
    String? position,
    String? department,
    String? fcmToken,
    bool? isOnSite,
    bool? isAdmin,
    DateTime? fcmTokenUpdatedAt,
    int? claimsVersion,
  }) {
    return Employee(
      clockNo: clockNo ?? this.clockNo,
      name: name ?? this.name,
      position: position ?? this.position,
      department: department ?? this.department,
      fcmToken: fcmToken ?? this.fcmToken,
      isOnSite: isOnSite ?? this.isOnSite,
      isAdmin: isAdmin ?? this.isAdmin,
      fcmTokenUpdatedAt: fcmTokenUpdatedAt ?? this.fcmTokenUpdatedAt,
      claimsVersion: claimsVersion ?? this.claimsVersion,
    );
  }
}