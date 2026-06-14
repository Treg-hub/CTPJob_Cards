import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_txn_type.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;

String inkTxnLabel(InkTxnType t) => switch (t) {
      InkTxnType.purchase => 'Purchase',
      InkTxnType.manufacture => 'Manufacture',
      InkTxnType.opening => 'Opening balance',
      InkTxnType.recovery => 'Recovery',
      InkTxnType.consumptionMeter => 'Meter consumption',
      InkTxnType.consumptionProduction => 'Production input',
      InkTxnType.consumptionTolulWash => 'IBC wash',
      InkTxnType.consumptionTolulProduction => 'Production solvent',
      InkTxnType.adjustment => 'Adjustment',
      InkTxnType.revaluation => 'Revaluation',
      InkTxnType.transfer => 'Transfer',
      InkTxnType.correction => 'Correction',
    };

/// Stock item detail — the read-back surface: current position + the full
/// append-only ledger for one item (newest first), with cached balance/WAC.
class InkStockItemDetailScreen extends ConsumerWidget {
  const InkStockItemDetailScreen({super.key, required this.itemCode});
  final String itemCode;

  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _df = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsValue = ref.watch(inkStockItemsProvider);
    final items = itemsValue.valueOrNull ?? [];
    InkStockItem? item;
    for (final i in items) {
      if (i.itemCode == itemCode) item = i;
    }
    final ledgerAsync = ref.watch(inkItemLedgerProvider(itemCode));
    final scheme = Theme.of(context).colorScheme;
    // Operators see quantities only — never WAC / value (cost is manager-only).
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(title: Text(item?.displayName ?? itemCode)),
      body: Column(
        children: [
          if (itemsValue.hasError)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Could not load item details.',
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          if (item != null)
            Card(
              margin: const EdgeInsets.all(12),
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _stat(context, 'Balance',
                        '${_qty.format(item.currentBalance)} ${item.unit}'),
                    if (isManager)
                      _stat(context, 'WAC',
                          _money.format(item.weightedAverageCost)),
                    if (isManager)
                      _stat(context, 'Value', _money.format(item.value)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ledgerAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (txns) {
                if (txns.isEmpty) {
                  return const Center(child: Text('No transactions yet.'));
                }
                final ordered = txns.reversed.toList();
                return ListView.separated(
                  itemCount: ordered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = ordered[i];
                    final positive = t.quantityDelta >= 0;
                    return ListTile(
                      dense: true,
                      leading: t.voided
                          ? Icon(Icons.cancel_outlined,
                              color: scheme.onSurfaceVariant, size: 20)
                          : t.flaggedForReview
                              ? Icon(Icons.flag, color: scheme.error)
                              : null,
                      title: Text(
                        inkTxnLabel(t.type),
                        style: t.voided
                            ? TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: scheme.onSurfaceVariant)
                            : null,
                      ),
                      subtitle: Text(
                        '${_df.format(t.effectiveAt)}'
                        '${t.seqNumber != null ? ' · ${t.seqNumber}' : ' · pending #'}'
                        '${t.voided ? ' · VOIDED' : ' · bal ${_qty.format(t.balanceAfter)}'}'
                        '${!t.voided && isManager ? ' @ ${_money.format(t.wacAtTime)}' : ''}',
                        style: t.voided
                            ? TextStyle(color: scheme.onSurfaceVariant)
                            : null,
                      ),
                      trailing: Text(
                        '${positive ? '+' : ''}${_qty.format(t.quantityDelta)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: t.voided
                              ? scheme.onSurfaceVariant
                              : positive
                                  ? Colors.green
                                  : scheme.error,
                          decoration:
                              t.voided ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onPrimaryContainer)),
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
