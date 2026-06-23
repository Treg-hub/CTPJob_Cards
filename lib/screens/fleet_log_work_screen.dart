import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fleet_edit_work_screen.dart';
import 'fleet_log_other_work_screen.dart';
import 'fleet_mark_fixed_screen.dart';

/// Backward-compatible router — delegates to focused task screens.
class FleetLogWorkScreen extends ConsumerWidget {
  final String? preSelectedAssetId;
  final String? preSelectedAssetName;
  final String? linkedIssueId;
  final String? workRecordId;
  final String? preSelectedWorkTypeLabel;

  const FleetLogWorkScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedAssetName,
    this.linkedIssueId,
    this.workRecordId,
    this.preSelectedWorkTypeLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workRecordId != null) {
      return FleetEditWorkScreen(workRecordId: workRecordId!);
    }
    if (linkedIssueId != null && preSelectedAssetId != null) {
      return FleetMarkFixedScreen(
        preSelectedAssetId: preSelectedAssetId!,
        preSelectedAssetName: preSelectedAssetName,
        linkedIssueId: linkedIssueId!,
      );
    }
    return FleetLogOtherWorkScreen(
      preSelectedAssetId: preSelectedAssetId,
      preSelectedWorkTypeLabel: preSelectedWorkTypeLabel,
    );
  }
}