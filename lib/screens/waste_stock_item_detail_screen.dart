import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/waste_stock_item.dart';
import '../utils/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';

class WasteStockItemDetailScreen extends ConsumerWidget {
  const WasteStockItemDetailScreen({super.key, required this.item});

  final WasteStockItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = Theme.of(context).appColors;
    final surfaceBg = appColors.wasteGreenSurface;
    final onSurface = onColor(surfaceBg);

    return Scaffold(
      appBar: WasteAppBar(title: 'Stock Item Detail'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: appColors.wasteGreen, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.layers, color: appColors.wasteGreen),
                      const SizedBox(width: 8),
                      Text(item.subtype,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: onSurface)),
                      const Spacer(),
                      _StatusBadge(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.scale,
                    label: 'Estimated weight',
                    value: item.estimatedWeightKg != null
                        ? '~${formatSAWeight(item.estimatedWeightKg!)}'
                        : 'Not recorded',
                    onSurface: onSurface,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Recorded by',
                    value: '${item.createdByName} (${item.createdBy})',
                    onSurface: onSurface,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: formatSADateTime(item.createdAt),
                    onSurface: onSurface,
                  ),
                  if (item.loadId != null) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.link,
                      label: 'Assigned to load',
                      value: item.loadId!,
                      onSurface: onSurface,
                    ),
                  ],
                ],
              ),
            ),

            // ── Notes ────────────────────────────────────────────
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes',
                  style: TextStyle(fontSize: 12, color: appColors.textMuted)),
              const SizedBox(height: 4),
              Text(item.notes!, style: const TextStyle(fontSize: 14)),
            ],

            // ── Photos ───────────────────────────────────────────
            const SizedBox(height: 16),
            Text('Photos (${item.photos.length})',
                style: TextStyle(fontSize: 12, color: appColors.textMuted)),
            const SizedBox(height: 8),
            item.photos.isEmpty
                ? Text('No photos',
                    style: TextStyle(color: appColors.textMuted, fontSize: 13))
                : GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: item.photos
                        .map((url) => _PhotoTile(url: url))
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final WasteStockStatus status;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status.displayLabel,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onSurface,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: onSurface.withAlpha(180)),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(fontSize: 12, color: onSurface.withAlpha(180))),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: onSurface,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          },
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
        ),
      ),
    );
  }
}
