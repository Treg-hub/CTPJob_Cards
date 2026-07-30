import 'package:flutter/material.dart';

import '../models/copper_inventory.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_stock_source.dart';
import '../services/copper_service.dart';
import '../services/waste_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Manager-only summary of copper ready for Waste collection.
///
/// Hidden until rods + nuggets total ≥ [kCopperWasteCollectionThresholdKg]
/// (inventory sell mirrors and/or on-site copper waste stock pools).
class WasteCopperReadyPanel extends StatelessWidget {
  const WasteCopperReadyPanel({
    super.key,
    required this.wasteService,
  });

  final WasteService wasteService;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    final surfaceBg = appColors.wasteGreenSurface.withValues(alpha: 0.35);
    final onSurface = onColor(surfaceBg);

    return StreamBuilder<CopperInventory>(
      stream: CopperService().getInventoryStream(),
      builder: (context, copperSnap) {
        return FutureBuilder<List<WasteStockItem>>(
          future: wasteService.fetchAllStockOnSiteOnce(),
          builder: (context, stockSnap) {
            final inv = copperSnap.data;
            final stock = (stockSnap.data ?? [])
                .where((i) =>
                    i.source.isCopperSellStaging &&
                    !i.isDeleted &&
                    i.status == WasteStockStatus.onSite)
                .toList();

            final rodsPending = inv?.sellRodsKg ?? 0.0;
            final nuggetsPending = inv?.sellNuggetsKg ?? 0.0;
            // Prefer rods+nuggets split; fall back to sellKg if split not populated.
            final pendingInModule = inv == null
                ? 0.0
                : (rodsPending + nuggetsPending > 0
                    ? rodsPending + nuggetsPending
                    : inv.sellKg);
            final onSiteKg = stock.fold<double>(
              0,
              (sum, i) => sum + (i.estimatedWeightKg ?? 0),
            );

            // Waste only surfaces copper once total is collection-ready.
            final readyKg =
                pendingInModule >= onSiteKg ? pendingInModule : onSiteKg;
            if (!copperMeetsWasteCollectionThreshold(readyKg)) {
              return const SizedBox.shrink();
            }

            final lines = <String>[];
            final showKg =
                pendingInModule > 0 ? pendingInModule : onSiteKg;
            lines.add(
              'Ready for collection: ${formatSAWeight(showKg)}'
              '${rodsPending > 0 || nuggetsPending > 0 ? ' (Rods ${formatSAWeight(rodsPending)} · Nuggets ${formatSAWeight(nuggetsPending)})' : ''}'
              ' — link From stock when collecting Copper Waste',
            );
            if (stock.isNotEmpty) {
              lines.add(
                'On-site waste stock: ${formatSAWeight(onSiteKg)}'
                ' (${stock.length} item${stock.length == 1 ? '' : 's'})',
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: surfaceBg,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sell_outlined, size: 18, color: onSurface),
                          const SizedBox(width: 8),
                          Text(
                            'Copper ready to collect',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...lines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            line,
                            style: TextStyle(fontSize: 12, color: onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
