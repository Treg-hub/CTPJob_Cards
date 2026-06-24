import 'package:flutter/material.dart';

import '../models/fleet_daily_check.dart';
import '../models/fleet_asset.dart';
import '../services/fleet_service.dart';
import 'fleet_daily_check_screen.dart';

/// @deprecated Use [FleetDailyCheckScreen] — kept for deep-link compatibility.
class FleetDailyCheckEndScreen extends StatelessWidget {
  const FleetDailyCheckEndScreen({super.key, required this.check});

  final FleetDailyCheck check;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FleetAsset?>(
      future: FleetService().getAsset(check.assetId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final asset = snap.data;
        if (asset == null) {
          return const Scaffold(
            body: Center(child: Text('Machine not found.')),
          );
        }
        return FleetDailyCheckScreen(asset: asset);
      },
    );
  }
}