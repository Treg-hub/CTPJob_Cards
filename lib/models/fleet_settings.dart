import 'package:cloud_firestore/cloud_firestore.dart';

/// Global Fleet configuration stored in fleet_settings/config.
class FleetSettings {
  final List<String> reporterDepartments;
  final List<String> costManagerClockNos;
  final List<String> mechanicClockNos;
  final bool fleetEnabled;
  final bool oosNotifyMechanic;
  final bool oosNotifyCostManagers;

  const FleetSettings({
    this.reporterDepartments = const [],
    this.costManagerClockNos = const [],
    this.mechanicClockNos = const [],
    this.fleetEnabled = false,
    this.oosNotifyMechanic = true,
    this.oosNotifyCostManagers = true,
  });

  static const FleetSettings defaults = FleetSettings();

  factory FleetSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetSettings(
      reporterDepartments: (data['reporter_departments'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      costManagerClockNos: (data['cost_manager_clock_nos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      mechanicClockNos: (data['mechanic_clock_nos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fleetEnabled: data['fleet_enabled'] as bool? ?? false,
      oosNotifyMechanic: data['oos_notify_mechanic'] as bool? ?? true,
      oosNotifyCostManagers: data['oos_notify_cost_managers'] as bool? ?? true,
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
    };
  }

  FleetSettings copyWith({
    List<String>? reporterDepartments,
    List<String>? costManagerClockNos,
    List<String>? mechanicClockNos,
    bool? fleetEnabled,
    bool? oosNotifyMechanic,
    bool? oosNotifyCostManagers,
  }) {
    return FleetSettings(
      reporterDepartments: reporterDepartments ?? this.reporterDepartments,
      costManagerClockNos: costManagerClockNos ?? this.costManagerClockNos,
      mechanicClockNos: mechanicClockNos ?? this.mechanicClockNos,
      fleetEnabled: fleetEnabled ?? this.fleetEnabled,
      oosNotifyMechanic: oosNotifyMechanic ?? this.oosNotifyMechanic,
      oosNotifyCostManagers: oosNotifyCostManagers ?? this.oosNotifyCostManagers,
    );
  }
}
