import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_transaction.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;

/// Phase 1i — Pending Costs (manager). Lists receipts captured cost-pending and
/// lets a manager enter the total cost and correct the effective date.
/// Setting the cost flips the receipt to `costed`, triggering a WAC re-replay.
class InkPendingCostsScreen extends ConsumerWidget {
  const InkPendingCostsScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('d MMM yyyy HH:mm');

  Future<void> _editDate(
      BuildContext context, WidgetRef ref, InkTransaction txn) async {
    final picked = await pickInkDateTime(context, txn.effectiveAt);
    if (picked == null || picked == txn.effectiveAt) return;
    if (txn.id == null) return;
    await ref.read(inkServiceProvider).setReceiptEffectiveAt(txn.id!, picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Effective date updated.')));
    }
  }

  Future<void> _enterCost(
      BuildContext context, WidgetRef ref, InkTransaction txn, String unit) async {
    final ctrl = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter total cost'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_qty.format(txn.quantityDelta)} $unit'
                '${txn.supplierName != null ? ' · ${txn.supplierName}' : ''}'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  prefixText: 'R ', labelText: 'Total cost'),
              onSubmitted: (v) =>
                  Navigator.pop(ctx, double.tryParse(v.trim())),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && value >= 0 && txn.id != null) {
      if (value == 0) {
        if (!context.mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Zero cost?'),
            content: const Text(
                'Setting the total cost to R 0.00 is unusual. Confirm?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm')),
            ],
          ),
        );
        if (ok != true) return;
      }
      await ref.read(inkServiceProvider).setPurchaseCost(txn.id!, value);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cost saved — WAC will recompute.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pending Costs')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final pendingAsync = ref.watch(inkPendingCostsProvider);
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final byCode = {
      for (final i in (itemsAsync.valueOrNull ?? [])) i.itemCode: i,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Costs')),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txns) => txns.isEmpty
            ? const Center(child: Text('No receipts awaiting a cost.'))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: txns.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = txns[i];
                  final item = byCode[t.stockItemCode];
                  final unit = item?.unit ?? '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payments_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item?.displayName ?? t.stockItemCode,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 26),
                          child: Text(
                            '${_qty.format(t.quantityDelta)} $unit'
                            '${t.supplierName != null ? ' · ${t.supplierName}' : ''}'
                            '${t.notes != null ? '\n${t.notes}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _editDate(context, ref, t),
                              icon: const Icon(Icons.event_outlined, size: 16),
                              label: Text(_df.format(t.effectiveAt)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                textStyle: Theme.of(context).textTheme.labelSmall,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const Spacer(),
                            FilledButton.tonal(
                              onPressed: () =>
                                  _enterCost(context, ref, t, unit),
                              child: const Text('Enter cost'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
