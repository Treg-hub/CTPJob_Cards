import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_asset_filter.dart';

/// Informational badge for today's daily safety check (non-blocking).
enum FleetCheckBadge { none, checkDue, done }

/// Reusable grid of fleet machine tiles (forklift, grab, BT).
class FleetAssetGrid extends StatelessWidget {
  const FleetAssetGrid({
    super.key,
    this.selectedAsset,
    required this.onAssetSelected,
    this.checkBadgeFor,
    this.maxHeight,
    this.selectable = true,
    this.reporterDepartment,
    this.sortAssets,
  });

  final FleetAsset? selectedAsset;
  final ValueChanged<FleetAsset> onAssetSelected;
  final FleetCheckBadge Function(FleetAsset asset)? checkBadgeFor;
  final double? maxHeight;
  final bool selectable;
  /// When set, only assets visible to this reporter department are shown.
  final String? reporterDepartment;
  /// Optional client-side sort after dept filter (e.g. check-due first).
  final List<FleetAsset> Function(List<FleetAsset> assets)? sortAssets;

  @override
  Widget build(BuildContext context) {
    final height = maxHeight ?? MediaQuery.sizeOf(context).height * 0.35;

    return SizedBox(
      height: height,
      child: StreamBuilder<List<FleetAsset>>(
        stream: FleetService().watchAssets(activeOnly: true),
        builder: (context, snapshot) {
          var assets = filterAssetsForReporter(
            snapshot.data ?? const [],
            reporterDepartment,
          );
          if (sortAssets != null) {
            assets = sortAssets!(assets);
          } else {
            assets.sort((a, b) => a.name.compareTo(b.name));
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              assets.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (assets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  reporterDepartment != null
                      ? 'No machines for your department — ask admin to assign departments on the register.'
                      : 'No machines available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).appColors.textMuted,
                  ),
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisExtent: 100,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: assets.length,
            itemBuilder: (context, index) {
              final asset = assets[index];
              return FleetAssetTile(
                asset: asset,
                isSelected: selectable && selectedAsset?.id == asset.id,
                checkBadge: checkBadgeFor?.call(asset) ?? FleetCheckBadge.none,
                onTap: () => onAssetSelected(asset),
              );
            },
          );
        },
      ),
    );
  }
}

class FleetAssetTile extends StatelessWidget {
  const FleetAssetTile({
    super.key,
    required this.asset,
    required this.isSelected,
    required this.onTap,
    this.checkBadge = FleetCheckBadge.none,
  });

  final FleetAsset asset;
  final bool isSelected;
  final VoidCallback onTap;
  final FleetCheckBadge checkBadge;

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
            ] else if (checkBadge != FleetCheckBadge.none) ...[
              const SizedBox(height: 2),
              Text(
                _badgeLabel(checkBadge),
                style: TextStyle(
                  fontSize: 9,
                  color: _badgeColor(context, checkBadge),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _badgeLabel(FleetCheckBadge badge) => switch (badge) {
        FleetCheckBadge.checkDue => 'Check due',
        FleetCheckBadge.done => 'Done',
        FleetCheckBadge.none => '',
      };

  static Color _badgeColor(BuildContext context, FleetCheckBadge badge) {
    final theme = Theme.of(context);
    return switch (badge) {
      FleetCheckBadge.checkDue => kBrandOrange,
      FleetCheckBadge.done => theme.appColors.statusCompleted,
      FleetCheckBadge.none => theme.appColors.textMuted,
    };
  }
}