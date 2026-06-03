import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';

/// Cost entry screen for fleet cost managers. Full implementation in Task 8.
class FleetAddCostScreen extends ConsumerStatefulWidget {
  final String? preSelectedAssetId;
  final String? preSelectedAssetName;
  final String? preSelectedWorkRecordId;
  final String? preSelectedWorkNumber;

  const FleetAddCostScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedAssetName,
    this.preSelectedWorkRecordId,
    this.preSelectedWorkNumber,
  });

  @override
  ConsumerState<FleetAddCostScreen> createState() => _FleetAddCostScreenState();
}

class _FleetAddCostScreenState extends ConsumerState<FleetAddCostScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Cost'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Cost entry form — coming in next build.'),
      ),
    );
  }
}
