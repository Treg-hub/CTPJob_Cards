import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_settings.dart';
import '../widgets/fleet_asset_grid.dart';
import 'role.dart' as role_utils;

/// Returns true when the reporter has not completed today's start check.
bool fleetAssetNeedsDailyCheck({
  required FleetAsset asset,
  required FleetDailyCheck? todayCheck,
  required FleetDailyChecklistConfig checklistConfig,
  required FleetSettings settings,
}) {
  if (!checklistConfig.enabled) return false;
  final emp = currentEmployee;
  if (emp == null) return false;
  if (!role_utils.isFleetReporter(emp, settings)) return false;
  if (todayCheck?.hasStart == true) return false;
  return true;
}

/// Badge for today's check state (informational only — does not block reporting).
FleetCheckBadge fleetCheckBadgeForAsset({
  required FleetAsset asset,
  required FleetDailyCheck? todayCheck,
  required FleetDailyChecklistConfig checklistConfig,
  required FleetSettings settings,
}) {
  if (!checklistConfig.enabled) return FleetCheckBadge.none;
  final emp = currentEmployee;
  if (emp == null) return FleetCheckBadge.none;
  if (!role_utils.isFleetReporter(emp, settings)) return FleetCheckBadge.none;

  if (todayCheck == null || !todayCheck.hasStart) {
    return FleetCheckBadge.checkDue;
  }
  if (todayCheck.hasEnd) {
    return FleetCheckBadge.done;
  }
  if (todayCheck.start?.driverClockNo == emp.clockNo) {
    return FleetCheckBadge.endShift;
  }
  return FleetCheckBadge.none;
}