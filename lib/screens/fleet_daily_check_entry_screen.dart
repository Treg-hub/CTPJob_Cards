import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../utils/presence_gating.dart';
import 'fleet_reporter_home_screen.dart';

/// Opens the reporter Machines tab (shared grid with Fleet tab).
Future<void> openFleetDailyCheckEntry(BuildContext context, WidgetRef ref) async {
  final settings = await FleetService().getSettings();
  final isOnSite = realEmployee?.isOnSite ?? true;
  if (!PresenceGating.canUseReporterFleetActions(
    emp: currentEmployee,
    settings: settings,
    isOnSite: isOnSite,
  )) {
    if (context.mounted) {
      PresenceGating.showOffSiteSnackBar(
        context,
        PresenceGating.offSiteReporterFleetMessage,
      );
    }
    return;
  }
  ref.read(fleetReporterShellTabProvider.notifier).state = 0;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const FleetReporterHomeScreen(
        initialTab: 0,
        standalone: true,
      ),
    ),
  );
}