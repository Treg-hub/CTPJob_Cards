import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import '../screens/fleet_daily_check_screen.dart';
import '../screens/fleet_report_wizard_screen.dart' show openFleetReportWizard;
import '../theme/app_theme.dart';

/// Machine tile tap — report a fault or open the daily safety checklist.
Future<void> showFleetMachineActionSheet(
  BuildContext context, {
  required FleetAsset asset,
  bool checklistEnabled = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => _FleetMachineActionSheet(
      asset: asset,
      checklistEnabled: checklistEnabled,
    ),
  );
}

class _FleetMachineActionSheet extends StatelessWidget {
  const _FleetMachineActionSheet({
    required this.asset,
    required this.checklistEnabled,
  });

  final FleetAsset asset;
  final bool checklistEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            asset.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'What do you want to do?',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              openFleetReportWizard(
                context,
                preSelectedAsset: asset,
              );
            },
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Report a problem'),
            style: FilledButton.styleFrom(
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (checklistEnabled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FleetDailyCheckScreen(asset: asset),
                  ),
                );
              },
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Daily safety check'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}