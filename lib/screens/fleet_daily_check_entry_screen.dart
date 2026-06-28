import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_daily_check_gate.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_grid.dart';
import 'fleet_daily_check_screen.dart';

/// Opens the daily safety check machine picker (check-only — no fault report).
Future<void> openFleetDailyCheckEntry(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const FleetDailyCheckEntryScreen()),
  );
}

/// Reporter entry for pre-use daily checks — tap machine → checklist directly.
class FleetDailyCheckEntryScreen extends ConsumerStatefulWidget {
  const FleetDailyCheckEntryScreen({super.key});

  @override
  ConsumerState<FleetDailyCheckEntryScreen> createState() =>
      _FleetDailyCheckEntryScreenState();
}

class _FleetDailyCheckEntryScreenState
    extends ConsumerState<FleetDailyCheckEntryScreen> {
  final _service = FleetService();
  FleetDailyChecklistConfig _checklistConfig =
      FleetDailyChecklistConfig.defaults;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _service.getDailyChecklistConfig();
    if (mounted) setState(() => _checklistConfig = config);
  }

  void _openCheck(FleetAsset asset) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FleetDailyCheckScreen(asset: asset)),
    );
  }

  int _badgePriority(FleetCheckBadge badge) => switch (badge) {
        FleetCheckBadge.checkDue => 0,
        FleetCheckBadge.done => 1,
        FleetCheckBadge.none => 2,
      };

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(fleetSettingsProvider).valueOrNull;
    final colors = Theme.of(context).appColors;

    if (!_checklistConfig.enabled) {
      return Scaffold(
        appBar: const FleetAppBar(title: 'Daily Safety Check'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Daily safety checks are not enabled.\nAsk an admin to turn them on in CTP Pulse Settings.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const FleetAppBar(title: 'Daily Safety Check'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kBrandOrange.withValues(alpha: 0.08),
              border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.fact_check_outlined, color: kBrandOrange, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Only check machines you plan to use today. '
                    'Tap a machine to complete its pre-use safety check.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Which machine are you using?',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<FleetDailyCheck>>(
            stream: _service.watchDailyChecksForDate(),
            builder: (context, checkSnap) {
              final checks = checkSnap.data ?? [];
              final checkByAsset = {for (final c in checks) c.assetId: c};
              return FleetAssetGrid(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                selectable: false,
                selectedAsset: null,
                reporterDepartment: currentEmployee?.department,
                sortAssets: (assets) {
                  if (settings == null) return assets;
                  assets.sort((a, b) {
                    final badgeA = fleetCheckBadgeForAsset(
                      asset: a,
                      todayCheck: a.id != null ? checkByAsset[a.id] : null,
                      checklistConfig: _checklistConfig,
                      settings: settings,
                    );
                    final badgeB = fleetCheckBadgeForAsset(
                      asset: b,
                      todayCheck: b.id != null ? checkByAsset[b.id] : null,
                      checklistConfig: _checklistConfig,
                      settings: settings,
                    );
                    final cmp = _badgePriority(badgeA)
                        .compareTo(_badgePriority(badgeB));
                    if (cmp != 0) return cmp;
                    return a.name.compareTo(b.name);
                  });
                  return assets;
                },
                onAssetSelected: _openCheck,
                checkBadgeFor: (asset) {
                  if (settings == null || asset.id == null) {
                    return FleetCheckBadge.none;
                  }
                  return fleetCheckBadgeForAsset(
                    asset: asset,
                    todayCheck: checkByAsset[asset.id],
                    checklistConfig: _checklistConfig,
                    settings: settings,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Already done today? Machines show Done — tap to view the summary.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}