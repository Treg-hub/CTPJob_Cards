import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';

/// Phase 1c — Transfer IBC → tank. Marks the IBC transferred (ink stock is
/// unaffected — it was counted at receipt) and records the toloul used to wash
/// the emptied IBC as a `consumption_toloul_wash`.
class InkIbcTransferScreen extends ConsumerStatefulWidget {
  const InkIbcTransferScreen({super.key});

  @override
  ConsumerState<InkIbcTransferScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcTransferScreen> {
  static final _qty = NumberFormat('#,##0.##');
  final _washCtrl = TextEditingController();
  String? _ibcNumber;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _washCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _effectiveAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() => _effectiveAt =
          DateTime(d.year, d.month, d.day, _effectiveAt.hour, _effectiveAt.minute));
    }
  }

  Future<void> _submit(InkIbc ibc, String tolulItemCode) async {
    final wash = double.tryParse(_washCtrl.text.trim()) ?? 0;
    if (wash < 0) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).transferIbc(
            ibc: ibc,
            tolulItemCode: tolulItemCode,
            washLitres: wash,
            effectiveAt: _effectiveAt,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IBC transferred; wash recorded.')));
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
    final ibcsAsync = ref.watch(inkReceivedIbcsProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final names = {for (final i in items) i.itemCode: i.displayName};
    String? tolulItemCode;
    for (final i in items) {
      if (i.itemClass == InkItemClass.solvent) tolulItemCode = i.itemCode;
    }
    final df = DateFormat('EEE d MMM yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer IBC → Tank')),
      body: ibcsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (ibcs) {
          if (ibcs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No received IBCs awaiting transfer.')),
            );
          }
          InkIbc? selected;
          for (final i in ibcs) {
            if (i.ibcNumber == _ibcNumber) selected = i;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _ibcNumber,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'IBC', border: OutlineInputBorder()),
                items: [
                  for (final i in ibcs)
                    DropdownMenuItem(
                      value: i.ibcNumber,
                      child: Text(
                          '${i.ibcNumber} · ${names[i.itemCode] ?? i.itemCode} · ${_qty.format(i.kg)} kg'),
                    ),
                ],
                onChanged: (v) => setState(() => _ibcNumber = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _washCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Toloul used to wash',
                  suffixText: 'LTS',
                  border: OutlineInputBorder(),
                ),
              ),
              if (tolulItemCode == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('No toloul (solvent) item found — wash cannot be recorded.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                onPressed: (_submitting ||
                        selected == null ||
                        tolulItemCode == null)
                    ? null
                    : () => _submit(selected!, tolulItemCode!),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Transfer IBC'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          );
        },
      ),
    );
  }
}
