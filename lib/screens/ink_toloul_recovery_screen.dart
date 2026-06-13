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
import '../utils/ink_pickers.dart';

/// Phase 1g — Toloul Recovery. Records solvent recovered from the Lurgi
/// distillation as a `recovery` transaction (additive, valued at the CURRENT
/// WAC — recovery never moves WAC).
class InkTolulRecoveryScreen extends ConsumerStatefulWidget {
  const InkTolulRecoveryScreen({super.key});

  @override
  ConsumerState<InkTolulRecoveryScreen> createState() => _State();
}

class _State extends ConsumerState<InkTolulRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  String? _itemCode;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _itemCode == null) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    final txn = InkTransaction(
      type: InkTxnType.recovery,
      stockItemCode: _itemCode!,
      quantityDelta: double.parse(_qtyCtrl.text.trim()),
      effectiveAt: _effectiveAt,
      costStatus: InkCostStatus.na,
      lurgiSource: _sourceCtrl.text.trim().isEmpty ? null : _sourceCtrl.text.trim(),
      actorClockNo: emp?.clockNo ?? '',
      actorName: emp?.name ?? '',
      idempotencyKey: const Uuid().v4(),
    );
    try {
      await ref.read(inkServiceProvider).recordTransaction(txn);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recovery recorded.')));
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
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Toloul Recovery')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allItems) {
          final items = allItems
              .where((i) => i.itemClass == InkItemClass.solvent)
              .toList();
          if (_itemCode == null && items.length == 1) {
            _itemCode = items.first.itemCode;
          }
          InkStockItem? selected;
          for (final i in items) {
            if (i.itemCode == _itemCode) selected = i;
          }
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
                      labelText: 'Solvent', border: OutlineInputBorder()),
                  items: [
                    for (final i in items)
                      DropdownMenuItem(
                          value: i.itemCode,
                          child: Text('${i.displayName} (${i.unit})')),
                  ],
                  onChanged: (v) => setState(() => _itemCode = v),
                  validator: (v) => v == null ? 'Select the solvent' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Volume recovered',
                    suffixText: selected?.unit ?? 'LTS',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim());
                    if (d == null || d <= 0) return 'Enter a volume greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sourceCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Lurgi / source (optional)',
                      border: OutlineInputBorder()),
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
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Record recovery'),
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
