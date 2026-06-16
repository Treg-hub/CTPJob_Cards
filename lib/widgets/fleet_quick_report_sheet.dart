import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_reporter_widgets.dart';

class FleetQuickReportResult {
  final FleetAsset asset;
  final FleetIssueSeverity severity;

  const FleetQuickReportResult({required this.asset, required this.severity});
}

Future<FleetQuickReportResult?> showFleetQuickReportSheet(
    BuildContext context) {
  return showModalBottomSheet<FleetQuickReportResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _FleetQuickReportSheet(),
  );
}

class _FleetQuickReportSheet extends StatefulWidget {
  const _FleetQuickReportSheet();

  @override
  State<_FleetQuickReportSheet> createState() => _FleetQuickReportSheetState();
}

class _FleetQuickReportSheetState extends State<_FleetQuickReportSheet> {
  FleetAsset? _selectedAsset;
  FleetIssueSeverity _severity = FleetIssueSeverity.medium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SizedBox(
      height: maxHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Report a Problem',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Which machine?',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: colors.textMuted, fontWeight: FontWeight.w600),
            ),
          ),

          Expanded(
            child: StreamBuilder<List<FleetAsset>>(
              stream: FleetService().watchAssets(activeOnly: true),
              builder: (context, snapshot) {
                final assets = List<FleetAsset>.from(snapshot.data ?? [])
                  ..sort((a, b) => a.name.compareTo(b.name));

                if (snapshot.connectionState == ConnectionState.waiting &&
                    assets.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (assets.isEmpty) {
                  return Center(
                    child: Text(
                      'No assets available.',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  );
                }

                return GridView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    mainAxisExtent: 100,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: assets.length,
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    return _AssetTile(
                      asset: asset,
                      isSelected: _selectedAsset?.id == asset.id,
                      onTap: () => setState(() => _selectedAsset = asset),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'How urgent is it?',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: colors.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FleetIssueSeverity.values.map((s) {
                final isSelected = _severity == s;
                final chipColor = s == FleetIssueSeverity.outOfService
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary;
                return ChoiceChip(
                  label: Text(reporterSeverityLabel(s)),
                  selected: isSelected,
                  selectedColor: chipColor,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? onColor(chipColor)
                        : colors.chipUnselectedLabel,
                    fontWeight: FontWeight.w500,
                  ),
                  onSelected: (_) => setState(() => _severity = s),
                );
              }).toList(),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton.icon(
                onPressed: _selectedAsset == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          FleetQuickReportResult(
                            asset: _selectedAsset!,
                            severity: _severity,
                          ),
                        ),
                icon: const Icon(Icons.arrow_forward),
                label: _selectedAsset == null
                    ? const Text('Select a machine to continue')
                    : const Text('Continue to report'),
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.withValues(alpha: 0.25),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.isSelected,
    required this.onTap,
  });

  final FleetAsset asset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isOos = asset.hasOpenOosIssue;
    final accentColor = isOos ? theme.colorScheme.error : primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.15)
              : theme.appColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : theme.colorScheme.outlineVariant,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              asset.typeName.toLowerCase().contains('grab')
                  ? Icons.precision_manufacturing
                  : Icons.forklift,
              size: 30,
              color: accentColor,
            ),
            const SizedBox(height: 6),
            Text(
              asset.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: isSelected ? accentColor : theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isOos) ...[
              const SizedBox(height: 2),
              Text(
                'OOS',
                style: TextStyle(
                  fontSize: 9,
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
