import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';

/// Mechanic work logging screen. Full implementation in Task 7.
/// Stub present so issue detail screen can reference and navigate here.
class FleetLogWorkScreen extends ConsumerStatefulWidget {
  final String? preSelectedAssetId;
  final String? preSelectedAssetName;
  final String? linkedIssueId;

  const FleetLogWorkScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedAssetName,
    this.linkedIssueId,
  });

  @override
  ConsumerState<FleetLogWorkScreen> createState() => _FleetLogWorkScreenState();
}

class _FleetLogWorkScreenState extends ConsumerState<FleetLogWorkScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Work'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Work logging form — coming in next build.'),
      ),
    );
  }
}
