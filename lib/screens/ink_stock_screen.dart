import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;
import 'ink_stock_item_detail_screen.dart';

/// Manager stock overview — all items grouped by class, sorted by displayOrder,
/// with per-group value totals and a grand total footer. WAC and value are
/// hidden for non-managers even if they somehow navigate here.
class InkStockScreen extends ConsumerWidget {
  const InkStockScreen({super.key});

  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);

  static const _classOrder = [
    InkItemClass.ink,
    InkItemClass.solvent,
    InkItemClass.manufactured,
    InkItemClass.raw,
  ];

  static String _classLabel(InkItemClass c) => switch (c) {
        InkItemClass.ink => 'Ink',
        InkItemClass.solvent => 'Solvent',
        InkItemClass.manufactured => 'Manufactured',
        InkItemClass.raw => 'Raw Materials',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = role_utils
        .isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Overview')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load stock: $e')),
        data: (items) {
          // Sort each class group by displayOrder.
          final grouped = <InkItemClass, List<InkStockItem>>{};
          for (final i in items) {
            grouped.putIfAbsent(i.itemClass, () => []).add(i);
          }
          for (final list in grouped.values) {
            list.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          }

          final grandTotal =
              items.fold<double>(0, (s, i) => s + i.value);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    for (final cls in _classOrder)
                      if (grouped.containsKey(cls)) ...[
                        _GroupHeader(
                          label: _classLabel(cls),
                          items: grouped[cls]!,
                          showMoney: isManager,
                        ),
                        for (final item in grouped[cls]!)
                          _StockRow(
                            item: item,
                            showMoney: isManager,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InkStockItemDetailScreen(
                                    itemCode: item.itemCode),
                              ),
                            ),
                          ),
                      ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              if (isManager)
                Container(
                  color: scheme.primaryContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Text('Grand total',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(_money.format(grandTotal),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(
      {required this.label, required this.items, required this.showMoney});
  final String label;
  final List<InkStockItem> items;
  final bool showMoney;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groupValue = items.fold<double>(0, (s, i) => s + i.value);
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
          const Spacer(),
          if (showMoney)
            Text(
              NumberFormat.currency(symbol: 'R ', decimalDigits: 2)
                  .format(groupValue),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow(
      {required this.item, required this.showMoney, required this.onTap});
  final InkStockItem item;
  final bool showMoney;
  final VoidCallback onTap;

  IconData get _icon => switch (item.itemClass) {
        InkItemClass.ink => Icons.water_drop_outlined,
        InkItemClass.solvent => Icons.opacity_outlined,
        InkItemClass.manufactured => Icons.blender_outlined,
        InkItemClass.raw => Icons.inventory_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final negative = item.currentBalance < 0;
    final qty = NumberFormat('#,##0.##');
    final money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);

    return ListTile(
      dense: true,
      leading: Icon(_icon,
          color: negative ? scheme.error : scheme.primary, size: 20),
      title: Text(item.displayName),
      subtitle: Text(
        '${qty.format(item.currentBalance)} ${item.unit}'
        '${showMoney ? '  ·  WAC ${money.format(item.weightedAverageCost)}' : ''}',
        style: TextStyle(
          color: negative ? scheme.error : scheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      trailing: showMoney
          ? Text(
              money.format(item.value),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: negative ? scheme.error : null,
              ),
            )
          : Text(
              '${qty.format(item.currentBalance)} ${item.unit}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: negative ? scheme.error : null,
              ),
            ),
      onTap: onTap,
    );
  }
}
