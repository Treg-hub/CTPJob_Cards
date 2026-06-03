import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/waste_stock_item.dart';
import '../services/waste_service.dart';
import '../utils/formatters.dart';
import '../utils/role.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';
import 'waste_add_stock_item_screen.dart';
import 'waste_stock_item_detail_screen.dart';

class WasteStockInventoryScreen extends ConsumerStatefulWidget {
  const WasteStockInventoryScreen({super.key, this.wasteType = 'Paper Waste'});

  final String wasteType;

  @override
  ConsumerState<WasteStockInventoryScreen> createState() =>
      _WasteStockInventoryScreenState();
}

class _WasteStockInventoryScreenState
    extends ConsumerState<WasteStockInventoryScreen> {
  final WasteService _wasteService = WasteService();

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    final canAdd = isWasteUser(currentEmployee);

    return Scaffold(
      appBar: WasteAppBar(
        title: '${widget.wasteType} Stock',
        isOnSite: currentEmployee?.isOnSite,
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WasteAddStockItemScreen(wasteType: widget.wasteType),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Record Item'),
              backgroundColor: appColors.wasteGreen,
              foregroundColor: Colors.white,
            )
          : null,
      body: Column(
        children: [
          _StockSummaryCard(wasteService: _wasteService, wasteType: widget.wasteType),
          Expanded(
            child: StreamBuilder<List<WasteStockItem>>(
              stream: _wasteService.watchStockOnSite(widget.wasteType),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return _EmptyState(wasteType: widget.wasteType);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _StockItemCard(
                    item: items[i],
                    appColors: appColors,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WasteStockItemDetailScreen(item: items[i]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card — count + estimated weight
// ---------------------------------------------------------------------------

class _StockSummaryCard extends StatefulWidget {
  const _StockSummaryCard({required this.wasteService, required this.wasteType});
  final WasteService wasteService;
  final String wasteType;

  @override
  State<_StockSummaryCard> createState() => _StockSummaryCardState();
}

class _StockSummaryCardState extends State<_StockSummaryCard> {
  bool _loading = true;
  int _count = 0;
  double _totalKg = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await widget.wasteService.getStockSummary(widget.wasteType);
      if (mounted) {
        setState(() {
          _count = summary.count;
          _totalKg = summary.totalEstimatedKg;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    final surfaceBg = appColors.wasteGreenSurface;
    final onSurface = onColor(surfaceBg);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: appColors.wasteGreen, width: 1),
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: appColors.wasteGreen, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _Stat(
                        value: '$_count',
                        label: 'item${_count == 1 ? '' : 's'} on site',
                        color: onSurface,
                      ),
                      Container(
                        width: 1, height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: onSurface.withAlpha(60),
                      ),
                      _Stat(
                        value: _totalKg > 0 ? '~${formatSAWeight(_totalKg)}' : '—',
                        label: 'est. weight',
                        color: onSurface,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, color: color.withAlpha(180))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Individual stock item card
// ---------------------------------------------------------------------------

class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.appColors,
    required this.onTap,
  });
  final WasteStockItem item;
  final AppColors appColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: item.photos.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  item.photos.first,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _DefaultLeadingIcon(appColors: appColors),
                ),
              )
            : _DefaultLeadingIcon(appColors: appColors),
        title: Text(item.subtype,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${formatSADate(item.createdAt)} · ${item.createdByName}',
          style: TextStyle(fontSize: 12, color: appColors.textMuted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              item.estimatedWeightKg != null
                  ? '~${formatSAWeight(item.estimatedWeightKg!)}'
                  : '—',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            _StatusBadge(status: item.status, appColors: appColors),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DefaultLeadingIcon extends StatelessWidget {
  const _DefaultLeadingIcon({required this.appColors});
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: appColors.wasteGreen.withAlpha(30),
      child: Icon(Icons.layers, color: appColors.wasteGreen, size: 20),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.appColors});
  final WasteStockStatus status;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    switch (status) {
      case WasteStockStatus.onSite:
        bg = appColors.wasteGreen;
        break;
      case WasteStockStatus.loaded:
        bg = Colors.blue.shade600;
        break;
      case WasteStockStatus.disposed:
        bg = Colors.grey.shade500;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status.displayLabel,
          style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.wasteType});
  final String wasteType;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: appColors.textMuted),
            const SizedBox(height: 12),
            Text('No stock on site',
                style: TextStyle(fontSize: 16, color: appColors.textMuted)),
            const SizedBox(height: 6),
            Text('Tap + Record Item to add one.',
                style: TextStyle(fontSize: 13, color: appColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
