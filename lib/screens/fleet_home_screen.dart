import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../providers/fleet_provider.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import 'fleet_mechanic_home_screen.dart';
import 'fleet_reporter_home_screen.dart';

/// Fleet Maintenance entry — floor roles only (reporter + mechanic).
/// Cost managers and fleet admin use CTP Pulse.
class FleetHomeScreen extends ConsumerWidget {
  const FleetHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(fleetSettingsProvider);
    if (!settingsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final settings = settingsAsync.requireValue;
    if (!settings.fleetEnabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Fleet Maintenance is not enabled.\nAsk an admin to turn it on in CTP Pulse Settings.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final emp = currentEmployee;
    final isMechanic = role_utils.isFleetMechanic(emp, settings);
    final isReporter = role_utils.isFleetReporter(emp, settings);
    final isOnSite = realEmployee?.isOnSite ?? true;

    // Dual-role (reporter dept + mechanic clock): mechanic shell wins — floor
    // work is primary; 5th tab surfaces My reports for tracking.
    if (isReporter && !isMechanic) {
      if (!PresenceGating.canUseReporterFleetActions(
        emp: emp,
        settings: settings,
        isOnSite: isOnSite,
      )) {
        return const OffSiteBlockedScreen(
          title: 'Fleet Reporting',
          message: PresenceGating.offSiteReporterFleetMessage,
        );
      }
      return const FleetReporterHomeScreen();
    }
    return FleetMechanicHomeScreen(
      includeMyReportsTab: isReporter && isMechanic,
    );
  }
}