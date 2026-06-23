import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';

/// Reusable grid of fleet machine tiles (forklift, grab, BT).
/// [requiresDailyCheck] is a Phase 3 hook — always false until daily checks ship.
class FleetAssetGrid extends StatelessWidget {
  const FleetAssetGrid({
    super.key,
    required this.selectedAsset,
    required this.onAssetSelected,
    this.requiresDailyCheck,
    this.maxHeight,
  });

  final FleetAsset? selectedAsset;
  final ValueChanged<FleetAsset> onAssetSelected;
  final bool Function(FleetAsset asset)? requiresDailyCheck;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final height = maxHeight ?? MediaQuery.sizeOf(context).height * 0.35;

    return SizedBox(
      height: height,
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
                'No machines available.',
                style: TextStyle(color: Theme.of(context).appColors.textMuted),
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
                isSelected: selectedAsset?.id == asset.id,
                needsCheck: requiresDailyCheck?.call(asset) ?? false,
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
    this.needsCheck = false,
  });

  final FleetAsset asset;
  final bool isSelected;
  final VoidCallback onTap;
  final bool needsCheck;

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
            ] else if (needsCheck) ...[
              const SizedBox(height: 2),
              Text(
                'Check due',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.amber.shade800,
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