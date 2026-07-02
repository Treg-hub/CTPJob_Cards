import 'package:cloud_firestore/cloud_firestore.dart';

/// Global Site Security configuration stored in security_settings/config.
class SecuritySettings {
  final bool securityEnabled;
  final bool driverLicenceScanRequired;
  final bool employeeClockRequired;
  final bool purposeOfVisitRequired;
  final int licenseExpiryWarnDays;
  final List<String> costTypeSuggestions;
  final List<String> managerClockNos;
  final List<String> guardClockNos;
  final bool photosRequired;
  final bool denyNotifyManagers;

  const SecuritySettings({
    this.securityEnabled = true,
    this.driverLicenceScanRequired = true,
    this.employeeClockRequired = false,
    this.purposeOfVisitRequired = false,
    this.licenseExpiryWarnDays = 7,
    this.costTypeSuggestions = const [
      'Parking',
      'Escort',
      'Fuel',
      'Maintenance',
      'Toll',
      'Fine',
      'Other',
    ],
    this.managerClockNos = const [],
    this.guardClockNos = const [],
    this.photosRequired = false,
    this.denyNotifyManagers = true,
  });

  static const SecuritySettings defaults = SecuritySettings();

  static String normalizeClockNo(dynamic value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString().trim();
  }

  static List<String> _parseClockNoList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map(normalizeClockNo)
          .where((clock) => clock.isNotEmpty)
          .toList();
    }
    final single = normalizeClockNo(raw);
    return single.isEmpty ? const [] : [single];
  }

  factory SecuritySettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final suggestions = (data['cost_type_suggestions'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];
    return SecuritySettings(
      securityEnabled: data['security_enabled'] as bool? ?? true,
      driverLicenceScanRequired:
          data['driver_licence_scan_required'] as bool? ??
              data['id_scan_required'] as bool? ??
              true,
      employeeClockRequired:
          data['employee_clock_required'] as bool? ?? false,
      purposeOfVisitRequired:
          data['purpose_of_visit_required'] as bool? ?? false,
      licenseExpiryWarnDays:
          (data['license_expiry_warn_days'] as num?)?.toInt() ?? 7,
      costTypeSuggestions: suggestions.isNotEmpty
          ? suggestions
          : SecuritySettings.defaults.costTypeSuggestions,
      managerClockNos: _parseClockNoList(data['manager_clock_nos']),
      guardClockNos: _parseClockNoList(data['guard_clock_nos']),
      photosRequired: data['photos_required'] as bool? ?? false,
      denyNotifyManagers: data['deny_notify_managers'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'security_enabled': securityEnabled,
        'driver_licence_scan_required': driverLicenceScanRequired,
        'employee_clock_required': employeeClockRequired,
        'purpose_of_visit_required': purposeOfVisitRequired,
        'license_expiry_warn_days': licenseExpiryWarnDays,
        'cost_type_suggestions': costTypeSuggestions,
        'manager_clock_nos': managerClockNos,
        'guard_clock_nos': guardClockNos,
        'photos_required': photosRequired,
        'deny_notify_managers': denyNotifyManagers,
      };
}