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
import '../utils/screen_insets.dart';

/// Phase 1M — Revaluation (manager / admin only, under instruction from
/// accounts). Sets a new WAC for an item without changing quantity.
class InkRevaluationScreen extends ConsumerStatefulWidget {
  const InkRevaluationScreen({super.key});

  @override
  ConsumerState<InkRevaluationScreen> createState() => _State();
}

class _State extends ConsumerState<InkRevaluationScreen> {
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 4);
  static final _qty = NumberFormat('#,##0.##');
  final _formKey = GlobalKey<FormState>();
  final _wacCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _itemCode;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _wacCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit(InkStockItem item) async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (!guardPersonaSubmit(context)) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final txn = InkTransaction(
      type: InkTxnType.revaluation,
      stockItemCode: item.itemCode,
      quantityDelta: 0,
      newWac: double.parse(_wacCtrl.text.trim()),
      effectiveAt: _effectiveAt,
      costStatus: InkCostStatus.na,
      reason: _reasonCtrl.text.trim().isEmpty
          ? 'Revaluation'
          : _reasonCtrl.text.trim(),
      actorClockNo: emp?.clockNo ?? '',
      actorName: emp?.name ?? '',
      idempotencyKey: const Uuid().v4(),
    );
    try {
      await ref.read(inkServiceProvider).recordTransaction(txn);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revaluation recorded.')));
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
    final isManager = role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Revaluation')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final itemsAsync = ref.watch(inkStockItemsProvider);
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Revaluation')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          InkStockItem? selected;
          for (final i in items) {
            if (i.itemCode == _itemCode) selected = i;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: ScreenInsets.symmetricScroll(context),
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
                    '${selected.unit} @ ${_money.format(selected.weightedAverageCost)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _wacCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'New WAC',
                      prefixText: 'R '),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim());
                    if (d == null || d < 0) return 'Enter the new WAC';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Reason (accounts instruction)'),
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
                      : const Icon(Icons.check),
                  label: const Text('Record revaluation'),
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
