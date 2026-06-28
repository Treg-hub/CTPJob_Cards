import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../providers/fleet_provider.dart';
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

    // Dual-role (reporter dept + mechanic clock): mechanic shell wins — floor
    // work is primary; reporters still use home quick-action tiles.
    if (isReporter && !isMechanic) {
      return const FleetReporterHomeScreen();
    }
    return const FleetMechanicHomeScreen();
  }
}