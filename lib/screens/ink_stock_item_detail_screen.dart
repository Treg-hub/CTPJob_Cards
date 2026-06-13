import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_txn_type.dart';
import '../providers/ink_provider.dart';

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
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    InkStockItem? item;
    for (final i in items) {
      if (i.itemCode == itemCode) item = i;
    }
    final ledgerAsync = ref.watch(inkItemLedgerProvider(itemCode));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(item?.displayName ?? itemCode)),
      body: Column(
        children: [
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
                    _stat(context, 'WAC', _money.format(item.weightedAverageCost)),
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
                      leading: t.flaggedForReview
                          ? Icon(Icons.flag, color: scheme.error)
                          : null,
                      title: Text(inkTxnLabel(t.type)),
                      subtitle: Text(
                        '${_df.format(t.effectiveAt)}'
                        '${t.seqNumber != null ? ' · ${t.seqNumber}' : ' · pending #'}'
                        ' · bal ${_qty.format(t.balanceAfter)} @ ${_money.format(t.wacAtTime)}',
                      ),
                      trailing: Text(
                        '${positive ? '+' : ''}${_qty.format(t.quantityDelta)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: positive ? Colors.green : scheme.error,
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
