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
import '../utils/persona_audit.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;

/// Manager-only screen for entering a pure rand value adjustment (no qty change).
///
/// Used when accounts instruct a cost write-up or write-down without a physical
/// stock movement. The signed amount (positive = value increase, negative =
/// value decrease) is stored in [InkTransaction.totalCost] and the ledger engine
/// recalculates WAC as (balance × currentWac + amount) / balance.
class InkValueAdjustmentScreen extends ConsumerStatefulWidget {
  const InkValueAdjustmentScreen({super.key});

  @override
  ConsumerState<InkValueAdjustmentScreen> createState() => _State();
}

class _State extends ConsumerState<InkValueAdjustmentScreen> {
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 4);
  static final _money2 = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _qty = NumberFormat('#,##0.##');
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _itemCode;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  String? _previewWac(InkStockItem item) {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || item.currentBalance <= 0) return null;
    final newWac =
        (item.currentBalance * item.weightedAverageCost + amount) /
            item.currentBalance;
    return _money.format(newWac);
  }

  Future<void> _submit(InkStockItem item) async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim());
    if (!guardPersonaSubmit(context)) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final txn = InkTransaction(
      type: InkTxnType.valueAdjustment,
      stockItemCode: item.itemCode,
      quantityDelta: 0,
      totalCost: amount,
      effectiveAt: _effectiveAt,
      costStatus: InkCostStatus.na,
      reason: _reasonCtrl.text.trim().isEmpty
          ? 'Value adjustment'
          : _reasonCtrl.text.trim(),
      actorClockNo: emp?.clockNo ?? '',
      actorName: emp?.name ?? '',
      idempotencyKey: const Uuid().v4(),
    );
    try {
      await ref.read(inkServiceProvider).recordTransaction(txn);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Value adjustment recorded.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Value Adjustment')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final itemsAsync = ref.watch(inkStockItemsProvider);
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Value Adjustment')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          InkStockItem? selected;
          for (final i in items) {
            if (i.itemCode == _itemCode) selected = i;
          }
          final preview = selected != null ? _previewWac(selected) : null;
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _itemCode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Item'),
                  items: [
                    for (final i in items)
                      DropdownMenuItem(
                          value: i.itemCode,
                          child: Text('${i.displayName} (${i.unit})')),
                  ],
                  onChanged: (v) => setState(() => _itemCode = v),
                  validator: (v) => v == null ? 'Select an item' : null,
                ),
                if (selected != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Current: ${_qty.format(selected.currentBalance)} '
                    '${selected.unit} @ ${_money.format(selected.weightedAverageCost)}'
                    ' = ${_money2.format(selected.value)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Adjustment amount',
                    prefixText: 'R ',
                    helperText: 'Positive = value increase · Negative = value decrease',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim());
                    if (d == null) return 'Enter the rand adjustment amount';
                    return null;
                  },
                ),
                if (preview != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'New WAC after adjustment: $preview',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Reason (accounts instruction ref.)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text('Effective date: ${df.format(_effectiveAt)}'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      alignment: Alignment.centerLeft),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: (_submitting || selected == null)
                      ? null
                      : () => _submit(selected!),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.price_change),
                  label: const Text('Record value adjustment'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
