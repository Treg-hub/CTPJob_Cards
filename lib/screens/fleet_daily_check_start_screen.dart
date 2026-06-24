import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import 'fleet_daily_check_screen.dart';

/// @deprecated Use [FleetDailyCheckScreen] — kept for deep-link compatibility.
class FleetDailyCheckStartScreen extends StatelessWidget {
  const FleetDailyCheckStartScreen({super.key, required this.asset});

  final FleetAsset asset;

  @override
  Widget build(BuildContext context) => FleetDailyCheckScreen(asset: asset);
}