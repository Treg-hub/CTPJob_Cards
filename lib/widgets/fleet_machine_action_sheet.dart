import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/fleet_asset.dart';
import '../screens/fleet_daily_check_screen.dart';
import '../screens/fleet_report_wizard_screen.dart' show openFleetReportWizard;
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/presence_gating.dart';
import '../utils/screen_insets.dart';

/// Machine tile tap — report a fault or open the daily safety checklist.
Future<void> showFleetMachineActionSheet(
  BuildContext context, {
  required FleetAsset asset,
  bool checklistEnabled = true,
}) async {
  final settings = await FleetService().getSettings();
  final isOnSite = realEmployee?.isOnSite ?? true;
  final canReport = PresenceGating.canUseReporterFleetActions(
    emp: currentEmployee,
    settings: settings,
    isOnSite: isOnSite,
  );
  if (!context.mounted) return;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => _FleetMachineActionSheet(
      asset: asset,
      checklistEnabled: checklistEnabled && canReport,
      canReport: canReport,
    ),
  );
}

class _FleetMachineActionSheet extends StatelessWidget {
  const _FleetMachineActionSheet({
    required this.asset,
    required this.checklistEnabled,
    required this.canReport,
  });

  final FleetAsset asset;
  final bool checklistEnabled;
  final bool canReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + ScreenInsets.bottomSafe(context),
      ),
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
          if (canReport) ...[
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
          ] else
            Text(
              PresenceGating.offSiteReporterFleetMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textMuted, height: 1.4),
            ),
        ],
      ),
    );
  }
}