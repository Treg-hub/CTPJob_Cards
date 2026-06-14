import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/role.dart' as role_utils;
import 'ink_stock_item_detail_screen.dart' show inkTxnLabel;

/// Phase 1M — Corrections (manager). Reversing-entry model: the chosen
/// transaction is voided (preserved for audit) and a corrected transaction is
/// appended. The server re-replays and recomputes balance/WAC.
class InkCorrectionsScreen extends ConsumerStatefulWidget {
  const InkCorrectionsScreen({super.key});

  @override
  ConsumerState<InkCorrectionsScreen> createState() => _State();
}

class _State extends ConsumerState<InkCorrectionsScreen> {
  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('d MMM yyyy');
  String? _itemCode;
  bool _correcting = false;

  static final _dtf = DateFormat('d MMM yyyy HH:mm');

  Future<void> _correct(InkTransaction original, String unit) async {
    final qtyCtrl =
        TextEditingController(text: original.quantityDelta.toString());
    final reasonCtrl = TextEditingController();
    var effectiveAt = original.effectiveAt;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Correct ${inkTxnLabel(original.type)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Original: ${_qty.format(original.quantityDelta)} $unit · '
                  '${_df.format(original.effectiveAt)}'
                  '${original.seqNumber != null ? ' · ${original.seqNumber}' : ''}'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Corrected quantity',
                    helperText: 'Signed — negative = out (consumption)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason *'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date: ${_dtf.format(effectiveAt)}',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    child: const Text('Edit date/time'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: effectiveAt,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (d == null || !ctx.mounted) return;
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(effectiveAt),
                      );
                      if (t == null) return;
                      setDlg(() => effectiveAt = DateTime(
                          d.year, d.month, d.day, t.hour, t.minute));
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply correction')),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final newQty = double.tryParse(qtyCtrl.text.trim());
    final reason = reasonCtrl.text.trim();
    if (newQty == null || reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a corrected quantity and a reason.')));
      return;
    }
    final allowed =
        await confirmClosedPeriodOverride(context, ref, effectiveAt);
    if (!allowed) return;
    setState(() => _correcting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    final correction = InkTransaction(
      type: original.type,
      stockItemCode: original.stockItemCode,
      quantityDelta: newQty,
      effectiveAt: effectiveAt,
      totalCost: original.totalCost,
      newWac: original.newWac,
      costStatus: original.costStatus,
      supplierName: original.supplierName,
      lurgiSource: original.lurgiSource,
      ibcNumber: original.ibcNumber,
      productionRunId: original.productionRunId,
      sessionId: original.sessionId,
      reason: 'Correction of ${original.seqNumber ?? original.id}: $reason',
      relatedTransactionId: original.id,
      actorClockNo: emp?.clockNo ?? '',
      actorName: emp?.name ?? '',
      idempotencyKey: const Uuid().v4(),
    );
    try {
      await ref
          .read(inkServiceProvider)
          .correctTransaction(original: original, correction: correction);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Correction applied.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _correcting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isManager = role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Corrections')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    InkStockItem? selected;
    for (final i in items) {
      if (i.itemCode == _itemCode) selected = i;
    }
    final ledgerAsync =
        _itemCode == null ? null : ref.watch(inkItemLedgerProvider(_itemCode!));

    return Scaffold(
      appBar: AppBar(title: const Text('Corrections')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _itemCode,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Item'),
              items: [
                for (final i in items)
                  DropdownMenuItem(
                      value: i.itemCode, child: Text('${i.displayName} (${i.unit})')),
              ],
              onChanged: (v) => setState(() => _itemCode = v),
            ),
          ),
          Expanded(
            child: ledgerAsync == null
                ? const Center(child: Text('Select an item to see its ledger.'))
                : ledgerAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (txns) {
                      final live = txns
                          .where((t) =>
                              !t.voided &&
                              t.type != InkTxnType.opening &&
                              t.type != InkTxnType.transfer &&
                              t.type != InkTxnType.correction)
                          .toList()
                          .reversed
                          .toList();
                      if (live.isEmpty) {
                        return const Center(
                            child: Text('No correctable transactions.'));
                      }
                      final unit = selected?.unit ?? '';
                      return ListView.separated(
                        itemCount: live.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = live[i];
                          return ListTile(
                            dense: true,
                            title: Text(inkTxnLabel(t.type)),
                            subtitle: Text(
                                '${_df.format(t.effectiveAt)}'
                                '${t.seqNumber != null ? ' · ${t.seqNumber}' : ''}'),
                            trailing: Text('${_qty.format(t.quantityDelta)} $unit'),
                            onTap: _correcting ? null : () => _correct(t, unit),
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
}
