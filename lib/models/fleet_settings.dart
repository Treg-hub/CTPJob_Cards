import 'package:cloud_firestore/cloud_firestore.dart';

/// Global Fleet configuration stored in fleet_settings/config.
class FleetSettings {
  final List<String> reporterDepartments;
  final List<String> costManagerClockNos;
  final List<String> mechanicClockNos;
  final bool fleetEnabled;
  final bool oosNotifyMechanic;
  final bool oosNotifyCostManagers;

  /// Monthly per-asset spend above which the Reports screen flags the asset.
  /// 0 (or unset) disables the flag.
  final double assetSpendAlertZar;

  const FleetSettings({
    this.reporterDepartments = const [],
    this.costManagerClockNos = const [],
    this.mechanicClockNos = const [],
    this.fleetEnabled = false,
    this.oosNotifyMechanic = true,
    this.oosNotifyCostManagers = true,
    this.assetSpendAlertZar = 0,
  });

  static const FleetSettings defaults = FleetSettings();

  /// Normalises clock numbers from Firestore (int `16`, string `"16"`, etc.).
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

  factory FleetSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetSettings(
      reporterDepartments: (data['reporter_departments'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      costManagerClockNos:
          _parseClockNoList(data['cost_manager_clock_nos']),
      mechanicClockNos: _parseClockNoList(data['mechanic_clock_nos']),
      fleetEnabled: data['fleet_enabled'] as bool? ?? false,
      oosNotifyMechanic: data['oos_notify_mechanic'] as bool? ?? true,
      oosNotifyCostManagers: data['oos_notify_cost_managers'] as bool? ?? true,
      assetSpendAlertZar:
          (data['asset_spend_alert_zar'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reporter_departments': reporterDepartments,
      'cost_manager_clock_nos': costManagerClockNos,
      'mechanic_clock_nos': mechanicClockNos,
      'fleet_enabled': fleetEnabled,
      'oos_notify_mechanic': oosNotifyMechanic,
      'oos_notify_cost_managers': oosNotifyCostManagers,
      'asset_spend_alert_zar': assetSpendAlertZar,
    };
  }

  FleetSettings copyWith({
    List<String>? reporterDepartments,
    List<String>? costManagerClockNos,
    List<String>? mechanicClockNos,
    bool? fleetEnabled,
    bool? oosNotifyMechanic,
    bool? oosNotifyCostManagers,
    double? assetSpendAlertZar,
  }) {
    return FleetSettings(
      reporterDepartments: reporterDepartments ?? this.reporterDepartments,
      costManagerClockNos: costManagerClockNos ?? this.costManagerClockNos,
      mechanicClockNos: mechanicClockNos ?? this.mechanicClockNos,
      fleetEnabled: fleetEnabled ?? this.fleetEnabled,
      oosNotifyMechanic: oosNotifyMechanic ?? this.oosNotifyMechanic,
      oosNotifyCostManagers: oosNotifyCostManagers ?? this.oosNotifyCostManagers,
      assetSpendAlertZar: assetSpendAlertZar ?? this.assetSpendAlertZar,
    );
  }
}
