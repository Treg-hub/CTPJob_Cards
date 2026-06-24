import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_settings.dart';
import '../providers/fleet_provider.dart';
import '../screens/fleet_daily_check_start_screen.dart';
import '../services/fleet_service.dart';
import 'role.dart' as role_utils;

/// Returns true when the reporter must complete today's start check first.
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

/// Opens the start check screen when required; returns true if gate passed.
Future<bool> ensureFleetDailyCheckGate(
  BuildContext context,
  WidgetRef ref,
  FleetAsset asset, {
  VoidCallback? onComplete,
}) async {
  final settings = ref.read(fleetSettingsProvider).valueOrNull;
  if (settings == null) return true;

  final service = FleetService();
  final config = await service.getDailyChecklistConfig();
  final todayCheck = await service.getDailyCheck(asset.id!);

  if (!fleetAssetNeedsDailyCheck(
    asset: asset,
    todayCheck: todayCheck,
    checklistConfig: config,
    settings: settings,
  )) {
    return true;
  }

  if (!context.mounted) return false;
  final completed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => FleetDailyCheckStartScreen(asset: asset),
    ),
  );
  if (completed == true) onComplete?.call();
  return completed == true;
}