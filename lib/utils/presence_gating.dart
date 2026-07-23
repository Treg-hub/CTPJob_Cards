import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/fleet_settings.dart';
import 'role.dart';

/// Client-side off-site presence rules for the Job Cards shell.
///
/// Only [isAdmin] bypasses off-site restrictions. Managers are not exempt.
/// Server-side enforcement remains deferred — this is UX + honest-user guard.
class PresenceGating {
  PresenceGating._();

  static const String offSiteModuleMessage =
      'This module is only available on-site. '
      'Return to the factory or wait for your location to update.';

  static const String offSiteCreateJobMessage =
      "You're marked off-site — job cards can only be created on-site. "
      'If this is wrong, open the app outdoors for a moment so your '
      'location can update.';

  static const String offSiteReporterFleetMessage =
      'Fleet reporting is only available on-site.';

  static bool bypassesOffSiteRestrictions(Employee? emp) => isAdmin(emp);

  /// Ink, Waste, Security modules and their home quick-action tiles.
  static bool canUseOnSiteOnlyModules({
    required Employee? emp,
    required bool isOnSite,
  }) =>
      isOnSite || bypassesOffSiteRestrictions(emp);

  /// Fleet module visibility (Home tile + auto-push for Hyster Mechanic).
  static bool showFleetTab({
    required Employee? emp,
    required FleetSettings? settings,
    required bool isOnSite,
  }) {
    if (settings == null || !settings.fleetEnabled) return false;
    if (bypassesOffSiteRestrictions(emp)) {
      return isFleetMobileUser(emp, settings);
    }
    if (isFleetMechanic(emp, settings)) return true;
    return isOnSite && isFleetReporter(emp, settings);
  }

  static bool canCreateJobCard({
    required Employee? emp,
    required bool isOnSite,
  }) =>
      isOnSite || bypassesOffSiteRestrictions(emp);

  /// Reporter quick actions: report problem, daily safety check, reporter shell.
  static bool canUseReporterFleetActions({
    required Employee? emp,
    required FleetSettings? settings,
    required bool isOnSite,
  }) {
    if (settings == null || !settings.fleetEnabled) return false;
    if (!isFleetReporter(emp, settings)) return false;
    return isOnSite || bypassesOffSiteRestrictions(emp);
  }

  static bool canDoFleetDailyCheckOffSiteAware({
    required Employee? emp,
    required FleetSettings? settings,
    required bool isOnSite,
  }) =>
      canUseReporterFleetActions(emp: emp, settings: settings, isOnSite: isOnSite);

  /// Reporter-only off-site (mechanics and dual-role keep fleet access).
  static bool isReporterOnlyOffSiteBlocked({
    required Employee? emp,
    required FleetSettings? settings,
    required bool isOnSite,
  }) {
    if (settings == null || !settings.fleetEnabled) return false;
    if (bypassesOffSiteRestrictions(emp)) return false;
    if (isFleetMechanic(emp, settings)) return false;
    return isFleetReporter(emp, settings) && !isOnSite;
  }

  static void showOffSiteSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange[800],
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

/// Full-screen guard when a module route is opened while off-site.
class OffSiteBlockedScreen extends StatelessWidget {
  const OffSiteBlockedScreen({
    super.key,
    this.title = 'On-site only',
    this.message = PresenceGating.offSiteModuleMessage,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}