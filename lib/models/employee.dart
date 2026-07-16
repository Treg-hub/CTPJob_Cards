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

  /// Presence transition timestamps, written by the native geofence/WorkManager
  /// paths and the updateEmployeePresence Cloud Function. Read-only on the
  /// client (NOT in toFirestore) so admin edits / CSV import never clobber them.
  /// `lastOnSiteAt` is the start of the current on-site session — used by the
  /// admin view's "on-site 14h+" stuck flag.
  final DateTime? lastOnSiteAt;
  final DateTime? lastOffSiteAt;

  /// Last client reported via updateEmployeePresence (web vs android).
  final String? clientPlatform;
  final String? clientDevice;
  final String? notificationDelivery;

  /// Last APK/web package version reported via presence sync (PackageInfo).
  /// Null on older builds that have not opened a Phase-0+ app yet.
  final String? clientAppVersion;
  final String? clientBuildNumber;

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
    this.lastOnSiteAt,
    this.lastOffSiteAt,
    this.clientPlatform,
    this.clientDevice,
    this.notificationDelivery,
    this.clientAppVersion,
    this.clientBuildNumber,
  });

  bool get isInboxOnlyDelivery => notificationDelivery == 'inbox_only';

  /// Admin On-site label, e.g. `v1.2.3 (build 160)` or null if never reported.
  String? get clientVersionLabel {
    final v = clientAppVersion?.trim();
    final b = clientBuildNumber?.trim();
    if ((v == null || v.isEmpty) && (b == null || b.isEmpty)) return null;
    if (v != null && v.isNotEmpty && b != null && b.isNotEmpty) {
      return 'v$v (build $b)';
    }
    if (v != null && v.isNotEmpty) return 'v$v';
    return 'build $b';
  }

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
      lastOnSiteAt: data['lastOnSiteAt'] is Timestamp
          ? (data['lastOnSiteAt'] as Timestamp).toDate()
          : null,
      lastOffSiteAt: data['lastOffSiteAt'] is Timestamp
          ? (data['lastOffSiteAt'] as Timestamp).toDate()
          : null,
      clientPlatform: data['clientPlatform'] as String?,
      clientDevice: data['clientDevice'] as String?,
      notificationDelivery: data['notificationDelivery'] as String?,
      clientAppVersion: data['clientAppVersion'] as String?,
      clientBuildNumber: data['clientBuildNumber']?.toString(),
    );
  }

  /// Client write payload for employees docs.
  ///
  /// **Does not include [isAdmin]** — admin is owned by locked `admins/{uid}`
  /// + `setCustomClaims` (Phase 9 dual isAdmin). Writing `isAdmin` here was a
  /// legacy path; merge sets must not re-stamp or clear the field.
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
    bool? isAdmin,
    DateTime? fcmTokenUpdatedAt,
    int? claimsVersion,
    DateTime? lastOnSiteAt,
    DateTime? lastOffSiteAt,
    String? clientPlatform,
    String? clientDevice,
    String? notificationDelivery,
    String? clientAppVersion,
    String? clientBuildNumber,
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
      lastOnSiteAt: lastOnSiteAt ?? this.lastOnSiteAt,
      lastOffSiteAt: lastOffSiteAt ?? this.lastOffSiteAt,
      clientPlatform: clientPlatform ?? this.clientPlatform,
      clientDevice: clientDevice ?? this.clientDevice,
      notificationDelivery:
          notificationDelivery ?? this.notificationDelivery,
      clientAppVersion: clientAppVersion ?? this.clientAppVersion,
      clientBuildNumber: clientBuildNumber ?? this.clientBuildNumber,
    );
  }
}