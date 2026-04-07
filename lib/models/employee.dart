import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String clockNo;
  final String name;
  final String position;
  final String department;
  final String? fcmToken;
  final bool isOnSite;
  final DateTime? fcmTokenUpdatedAt;

  const Employee({
    required this.clockNo,
    required this.name,
    required this.position,
    required this.department,
    this.fcmToken,
    this.isOnSite = true,
    this.fcmTokenUpdatedAt,
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
      fcmTokenUpdatedAt: data['fcmTokenUpdatedAt'] != null
          ? (data['fcmTokenUpdatedAt'] as Timestamp).toDate()
          : null,
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
    DateTime? fcmTokenUpdatedAt,
  }) {
    return Employee(
      clockNo: clockNo ?? this.clockNo,
      name: name ?? this.name,
      position: position ?? this.position,
      department: department ?? this.department,
      fcmToken: fcmToken ?? this.fcmToken,
      isOnSite: isOnSite ?? this.isOnSite,
      fcmTokenUpdatedAt: fcmTokenUpdatedAt ?? this.fcmTokenUpdatedAt,
    );
  }
}