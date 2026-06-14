import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;
import 'ink_stock_item_detail_screen.dart' show inkTxnLabel, InkStockItemDetailScreen;

/// Manager screen — flagged / negative-balance transaction review.
///
/// Shows every non-voided transaction that has [InkTransaction.flaggedForReview]
/// == true (sorted newest-effective first). Tapping a row opens the full item
/// ledger so the manager can inspect context and raise a correction.
class InkFlaggedReviewScreen extends ConsumerWidget {
  const InkFlaggedReviewScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _df = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flaggedAsync = ref.watch(inkFlaggedProvider);
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final byCode = <String, InkStockItem>{
      for (final i in (itemsAsync.valueOrNull ?? [])) i.itemCode: i,
    };

    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Flagged Transactions')),
      body: flaggedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          // Skip voided (already corrected) and sort newest-effective first.
          final txns = (all.where((t) => !t.voided).toList())
            ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));

          if (txns.isEmpty) {
            return const Center(
              child: _EmptyState(),
            );
          }

          return ListView.separated(
            itemCount: txns.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _FlaggedTile(
              txn: txns[i],
              byCode: byCode,
              qty: _qty,
              money: _money,
              df: _df,
              isManager: isManager,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'No flagged transactions — all good.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FlaggedTile extends StatelessWidget {
  const _FlaggedTile({
    required this.txn,
    required this.byCode,
    required this.qty,
    required this.money,
    required this.df,
    required this.isManager,
  });

  final InkTransaction txn;
  final Map<String, InkStockItem> byCode;
  final NumberFormat qty;
  final NumberFormat money;
  final DateFormat df;
  final bool isManager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = byCode[txn.stockItemCode];
    final displayName = item?.displayName ?? txn.stockItemCode;
    final unit = item?.unit ?? '';
    final signed = txn.quantityDelta >= 0
        ? '+${qty.format(txn.quantityDelta)}'
        : qty.format(txn.quantityDelta);
    final seqLabel =
        txn.seqNumber != null ? txn.seqNumber! : 'pending #';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.flag, color: scheme.error, size: 22),
      ),
      title: Text(
        '$displayName · ${inkTxnLabel(txn.type)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$signed $unit  ·  ${df.format(txn.effectiveAt)}  ·  $seqLabel',
          ),
          Text(
            'Balance after: ${qty.format(txn.balanceAfter)} $unit'
            '${isManager && txn.wacAtTime > 0 ? "  |  WAC ${money.format(txn.wacAtTime)}" : ""}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          if (txn.flagReason != null && txn.flagReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                txn.flagReason!,
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              InkStockItemDetailScreen(itemCode: txn.stockItemCode),
        ),
      ),
    );
  }
}
