import 'package:flutter/material.dart';

import '../models/copper_inventory.dart';
import '../models/waste_stock_item.dart';
import '../services/copper_service.dart';
import '../services/waste_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Manager-only summary of copper staged for collection (copper module sell
/// mirrors + on-site copper waste stock pools Security can link to a load).
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

            final pendingInModule = inv == null ? 0.0 : inv.sellKg;
            final rodsPending = inv?.sellRodsKg ?? 0.0;
            final nuggetsPending = inv?.sellNuggetsKg ?? 0.0;
            final onSiteKg = stock.fold<double>(
              0,
              (sum, i) => sum + (i.estimatedWeightKg ?? 0),
            );

            if (pendingInModule <= 0 && onSiteKg <= 0) {
              return const SizedBox.shrink();
            }

            final lines = <String>[];
            if (pendingInModule > 0 || onSiteKg > 0) {
              final showKg =
                  pendingInModule > 0 ? pendingInModule : onSiteKg;
              lines.add(
                'Staged for collection: ${formatSAWeight(showKg)}'
                '${rodsPending > 0 || nuggetsPending > 0 ? ' (Rods ${formatSAWeight(rodsPending)} · Nuggets ${formatSAWeight(nuggetsPending)})' : ''}'
                ' — link from stock when collecting Copper Waste',
              );
            }
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
