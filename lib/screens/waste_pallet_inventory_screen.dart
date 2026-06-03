import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/waste_pallet.dart';
import '../services/waste_service.dart';
import '../utils/formatters.dart';
import '../utils/role.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';
import 'waste_add_pallet_screen.dart';
import 'waste_pallet_detail_screen.dart';

class WastePalletInventoryScreen extends ConsumerStatefulWidget {
  const WastePalletInventoryScreen({super.key, this.wasteType = 'Paper Waste'});

  final String wasteType;

  @override
  ConsumerState<WastePalletInventoryScreen> createState() =>
      _WastePalletInventoryScreenState();
}

class _WastePalletInventoryScreenState
    extends ConsumerState<WastePalletInventoryScreen> {
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
                  builder: (_) => WasteAddPalletScreen(wasteType: widget.wasteType),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Record Pallet'),
              backgroundColor: appColors.wasteGreen,
              foregroundColor: Colors.white,
            )
          : null,
      body: Column(
        children: [
          _SummaryCard(wasteService: _wasteService, wasteType: widget.wasteType),
          Expanded(
            child: StreamBuilder<List<WastePallet>>(
              stream: _wasteService.watchPalletsOnSite(widget.wasteType),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final pallets = snap.data ?? [];
                if (pallets.isEmpty) {
                  return _EmptyState(wasteType: widget.wasteType);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: pallets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _PalletCard(
                    pallet: pallets[i],
                    appColors: appColors,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WastePalletDetailScreen(pallet: pallets[i]),
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
// Summary card — total on-site count + estimated weight
// ---------------------------------------------------------------------------

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({required this.wasteService, required this.wasteType});
  final WasteService wasteService;
  final String wasteType;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
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
      final summary = await widget.wasteService.getPalletSummary(widget.wasteType);
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
          ? const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: appColors.wasteGreen, size: 28),
                const SizedBox(width: 12),
                _StatPill(
                  label: '$_count pallet${_count == 1 ? '' : 's'} on site',
                  color: onSurface,
                ),
                const SizedBox(width: 16),
                _StatPill(
                  label: _totalKg > 0
                      ? '~${formatSAWeight(_totalKg)} est.'
                      : 'weight not recorded',
                  color: onSurface.withAlpha(200),
                ),
              ],
            ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color));
  }
}

// ---------------------------------------------------------------------------
// Individual pallet card in the list
// ---------------------------------------------------------------------------

class _PalletCard extends StatelessWidget {
  const _PalletCard({
    required this.pallet,
    required this.appColors,
    required this.onTap,
  });
  final WastePallet pallet;
  final AppColors appColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = formatSADate(pallet.createdAt);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: appColors.wasteGreen.withAlpha(30),
          child: Icon(Icons.layers, color: appColors.wasteGreen, size: 20),
        ),
        title: Text(pallet.subtype,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '$dateStr · ${pallet.createdByName}',
          style: TextStyle(fontSize: 12, color: appColors.textMuted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              pallet.estimatedWeightKg != null
                  ? '~${formatSAWeight(pallet.estimatedWeightKg!)}'
                  : '—',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            _StatusBadge(status: pallet.status, appColors: appColors),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.appColors});
  final WastePalletStatus status;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    switch (status) {
      case WastePalletStatus.onSite:
        bg = appColors.wasteGreen;
        break;
      case WastePalletStatus.loaded:
        bg = Colors.blue.shade600;
        break;
      case WastePalletStatus.disposed:
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
            Text('No pallets on site',
                style: TextStyle(fontSize: 16, color: appColors.textMuted)),
            const SizedBox(height: 6),
            Text('Tap + Record Pallet to add one.',
                style: TextStyle(fontSize: 13, color: appColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
