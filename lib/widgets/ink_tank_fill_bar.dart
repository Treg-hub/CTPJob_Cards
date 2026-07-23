import 'package:flutter/material.dart';

import '../constants/ink_toloul.dart';
import '../models/ink_tank_level.dart';
import '../theme/app_theme.dart';

/// Ink / binder / toloul colours for tank fill bars.
Color inkTankFillColor(String itemCode) {
  switch (itemCode) {
    case 'yellow':
      return const Color(0xFFF5C518);
    case 'red':
      return const Color(0xFFC62828);
    case 'blue':
      return const Color(0xFF1565C0);
    case 'black':
      return const Color(0xFF212121);
    case 'gravure_binder':
      return const Color(0xFF607D8B);
    case kToloulItemCode:
      return kBrandOrange;
    default:
      return kBrandOrange;
  }
}

/// Compact tank card: % full fill bar in ink colour; red chrome when low.
class InkTankLevelCard extends StatelessWidget {
  const InkTankLevelCard({
    super.key,
    required this.tank,
    this.compact = false,
  });

  final InkTankLevel tank;
  final bool compact;

  static final _qty = RegExp(r'\B(?=(\d{3})+(?!\d))');

  String _fmt(double v) {
    final s = v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
    return s.replaceAllMapped(_qty, (m) => '${m[0]},');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLow = tank.isLow;
    final accent = isLow ? kLowStockRed : inkTankFillColor(tank.itemCode);
    final tileColor = (isLow ? kLowStockRed : accent)
        .withValues(alpha: isLow ? 0.30 : 0.10);
    final borderColor = (isLow ? kLowStockRed : accent)
        .withValues(alpha: isLow ? 0.90 : 0.45);
    final textColor = Theme.of(context).brightness == Brightness.light
        ? Colors.black87
        : scheme.onSurface;
    final pct = tank.percentFull;
    final pctLabel = pct == null ? '—' : '${pct.round()}%';
    final fill = inkTankFillColor(tank.itemCode);
    final qtyLabel =
        '${_fmt(tank.balance)} ${tank.unit == 'LTS' ? 'L' : tank.unit}';

    return Card(
      elevation: 0,
      color: tileColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: isLow ? 1.4 : 0.8),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isLow) ...[
                  Icon(Icons.warning_amber_rounded,
                      size: compact ? 16 : 18, color: kLowStockRed),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    tank.displayName,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  pctLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct == null ? 0 : (pct / 100).clamp(0.0, 1.0),
                minHeight: compact ? 8 : 10,
                backgroundColor: fill.withValues(alpha: 0.18),
                color: fill,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              qtyLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.85),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
