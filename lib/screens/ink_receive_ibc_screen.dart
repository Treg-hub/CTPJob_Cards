import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';
import 'ink_barcode_scan_screen.dart';

class _IbcRow {
  _IbcRow({String number = ''})
      : numberCtrl = TextEditingController(text: number),
        kgCtrl = TextEditingController();
  final TextEditingController numberCtrl;
  String? itemCode;
  final TextEditingController kgCtrl;
}

/// Phase 1b — Receive Ink via IBC. Scan (Code-128) or type each IBC's number,
/// pick the colour and enter kg. On submit each IBC is registered (audit) and
/// stock is raised as ONE cost-pending `purchase` per colour for the total kg
/// (e.g. 10 IBCs → 11,403 kg as a single receipt); a manager enters the cost later.
class InkReceiveIbcScreen extends ConsumerStatefulWidget {
  const InkReceiveIbcScreen({super.key});

  @override
  ConsumerState<InkReceiveIbcScreen> createState() => _State();
}

class _State extends ConsumerState<InkReceiveIbcScreen> {
  String? _supplier;
  DateTime _effectiveAt = DateTime.now();
  final List<_IbcRow> _rows = [_IbcRow()];
  bool _submitting = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.numberCtrl.dispose();
      r.kgCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const InkBarcodeScanScreen()));
    if (code != null && code.isNotEmpty) {
      setState(() => _rows.add(_IbcRow(number: code)));
    }
  }

  Future<void> _submit() async {
    if (_supplier == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a supplier.')));
      return;
    }
    final ibcs = <InkIbc>[];
    for (final r in _rows) {
      final num = r.numberCtrl.text.trim();
      final kg = double.tryParse(r.kgCtrl.text.trim());
      if (num.isEmpty || r.itemCode == null || kg == null || kg <= 0) continue;
      ibcs.add(InkIbc(
          ibcNumber: num,
          itemCode: r.itemCode!,
          kg: kg,
          receivedDate: _effectiveAt));
    }
    if (ibcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one complete IBC (number, colour, kg).')));
      return;
    }
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).recordIbcReceipt(
            ibcs: ibcs,
            supplierName: _supplier!,
            effectiveAt: _effectiveAt,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${ibcs.length} IBC(s) received — cost pending.')));
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
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final inks =
        items.where((i) => i.itemClass == InkItemClass.ink).toList();
    final suppliers = ref.watch(inkActiveSuppliersProvider).valueOrNull ?? [];
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    final totalKg = _rows.fold<double>(
        0, (s, r) => s + (double.tryParse(r.kgCtrl.text.trim()) ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Ink (IBC)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _supplier,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Supplier', border: OutlineInputBorder()),
            items: [
              for (final s in suppliers)
                DropdownMenuItem(value: s.name, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _supplier = v),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text('Received: ${df.format(_effectiveAt)}'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                alignment: Alignment.centerLeft),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('IBCs (${_rows.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('Total: ${NumberFormat('#,##0.##').format(totalKg)} kg'),
            ],
          ),
          const SizedBox(height: 8),
          for (var idx = 0; idx < _rows.length; idx++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    TextField(
                      controller: _rows[idx].numberCtrl,
                      decoration: const InputDecoration(
                          labelText: 'IBC number',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _rows[idx].itemCode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Colour',
                                isDense: true,
                                border: OutlineInputBorder()),
                            items: [
                              for (final i in inks)
                                DropdownMenuItem(
                                    value: i.itemCode,
                                    child: Text(i.displayName)),
                            ],
                            onChanged: (v) =>
                                setState(() => _rows[idx].itemCode = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _rows[idx].kgCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'kg',
                                isDense: true,
                                border: OutlineInputBorder()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _rows.length == 1
                              ? null
                              : () => setState(() {
                                    _rows[idx].numberCtrl.dispose();
                                    _rows[idx].kgCtrl.dispose();
                                    _rows.removeAt(idx);
                                  }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _rows.add(_IbcRow())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add IBC'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Receive IBCs'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
