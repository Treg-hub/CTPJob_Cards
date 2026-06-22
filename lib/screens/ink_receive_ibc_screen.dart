import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../models/ink_shipment.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../services/ink_barcode_parser.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';
import '../utils/ink_receipt_validation.dart';
import 'ink_barcode_scan_screen.dart';

class _IbcRow {
  _IbcRow({String number = '', this.itemCode, String kg = '', this.charge})
      : numberCtrl = TextEditingController(text: number),
        kgCtrl = TextEditingController(text: kg);
  final TextEditingController numberCtrl;
  String? itemCode;
  final TextEditingController kgCtrl;
  String? charge; // Siegwerk batch/lot from the GS1 barcode
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
  final _orderCtrl = TextEditingController();
  final _cgnaCtrl = TextEditingController();
  DateTime _effectiveAt = DateTime.now();
  final List<_IbcRow> _rows = [_IbcRow()];
  bool _submitting = false;

  /// When set, the operator is receiving against this Pulse-created shipment:
  /// order/CGNA are prefilled, the colour list is restricted to its lines, and
  /// every IBC number is validated against its packing list.
  InkShipment? _shipment;

  void _selectShipment(InkShipment? s) {
    setState(() {
      _shipment = s;
      if (s != null) {
        _supplier = 'Siegwerk';
        _orderCtrl.text = s.orderNumber;
        _cgnaCtrl.text = s.cgnaNumber ?? '';
      }
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.numberCtrl.dispose();
      r.kgCtrl.dispose();
    }
    _orderCtrl.dispose();
    _cgnaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _scan() async {
    final res = await Navigator.push<IbcScanResult>(context,
        MaterialPageRoute(builder: (_) => const InkBarcodeScanScreen()));
    if (res == null || !res.hasAnything) return;
    final itemCode = res.colour?.toLowerCase();
    final kg = res.weightKg == null
        ? ''
        : (res.weightKg! % 1 == 0
            ? res.weightKg!.toInt().toString()
            : res.weightKg!.toString());
    setState(() {
      // Fill the first empty row, otherwise add a new prefilled one.
      final empties = _rows.where((r) =>
          r.numberCtrl.text.trim().isEmpty && r.kgCtrl.text.trim().isEmpty);
      if (empties.isNotEmpty) {
        final r = empties.first;
        if (res.ibcNumber != null) r.numberCtrl.text = res.ibcNumber!;
        if (itemCode != null) r.itemCode = itemCode;
        if (kg.isNotEmpty) r.kgCtrl.text = kg;
        r.charge = res.charge;
      } else {
        _rows.add(_IbcRow(
            number: res.ibcNumber ?? '',
            itemCode: itemCode,
            kg: kg,
            charge: res.charge));
      }
    });
  }

  /// Validates all rows and returns the complete IBC list, or null if invalid
  /// (shows a snackbar describing the first error found).
  List<InkIbc>? _buildValidIbcs() {
    if (_supplier == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a supplier.')));
      return null;
    }
    final ibcs = <InkIbc>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final numText = r.numberCtrl.text.trim();
      final kgText = r.kgCtrl.text.trim();
      final kg = double.tryParse(kgText);

      // Skip completely blank rows silently.
      if (numText.isEmpty && r.itemCode == null && kgText.isEmpty) continue;

      if (numText.length != 8) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Row ${i + 1}: IBC number must be exactly 8 digits.')));
        return null;
      }
      if (r.itemCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Row ${i + 1}: select a colour.')));
        return null;
      }
      if (kg == null || kg <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Row ${i + 1}: enter a valid weight.')));
        return null;
      }
      ibcs.add(InkIbc(
          ibcNumber: numText,
          itemCode: r.itemCode!,
          kg: kg,
          receivedDate: _effectiveAt,
          chargeNumber: r.charge));
    }
    if (ibcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one complete IBC (number, colour, kg).')));
      return null;
    }
    // When receiving against a shipment, every IBC must be on its packing list.
    if (_shipment != null) {
      final errors = validateIbcRowsAgainstShipment(
        shipment: _shipment!,
        rows: [
          for (final ibc in ibcs)
            IbcReceiptRow(ibcNumber: ibc.ibcNumber, itemCode: ibc.itemCode),
        ],
      );
      if (errors.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errors.first.message)));
        return null;
      }
    }
    return ibcs;
  }

  Future<void> _confirmAndSubmit() async {
    final ibcs = _buildValidIbcs();
    if (ibcs == null) return;

    final items = ref.read(inkStockItemsProvider).valueOrNull ?? [];
    final displayName = {for (final i in items) i.itemCode: i.displayName};

    // Group by colour for the summary.
    final summary = <String, ({int count, double kg})>{};
    for (final ibc in ibcs) {
      final prev = summary[ibc.itemCode];
      summary[ibc.itemCode] = prev == null
          ? (count: 1, kg: ibc.kg)
          : (count: prev.count + 1, kg: prev.kg + ibc.kg);
    }

    // Sort entries by the stock item displayOrder so the table is always consistent.
    final orderOf = {for (final i in items) i.itemCode: i.displayOrder};
    final sortedEntries = summary.entries.toList()
      ..sort((a, b) =>
          (orderOf[a.key] ?? 9999).compareTo(orderOf[b.key] ?? 9999));

    final nf = NumberFormat('#,##0.##');
    final totalKg = ibcs.fold<double>(0, (s, i) => s + i.kg);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text('Colour',
                          style: Theme.of(ctx)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.bold))),
                  SizedBox(
                      width: 44,
                      child: Text('IBCs',
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.bold))),
                  SizedBox(
                      width: 76,
                      child: Text('Total kg',
                          textAlign: TextAlign.right,
                          style: Theme.of(ctx)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            for (final entry in sortedEntries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                        flex: 4,
                        child: Text(displayName[entry.key] ?? entry.key)),
                    SizedBox(
                        width: 44,
                        child: Text('${entry.value.count}',
                            textAlign: TextAlign.center)),
                    SizedBox(
                        width: 76,
                        child: Text(nf.format(entry.value.kg),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                    flex: 4,
                    child: Text('Total',
                        style: Theme.of(ctx)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 44,
                    child: Text('${ibcs.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 76,
                    child: Text(nf.format(totalKg),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
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
              child: const Text('Receive IBCs')),
        ],
      ),
    );

    if (confirmed != true) return;
    await _doSubmit(ibcs);
  }

  Future<void> _doSubmit(List<InkIbc> ibcs) async {
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
            orderNumber: _orderCtrl.text.trim(),
            cgnaNumber: _cgnaCtrl.text.trim(),
            shipmentId: _shipment?.id,
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
    ref.listen(inkActiveSuppliersProvider, (_, next) {
      if (_supplier == null &&
          (next.valueOrNull ?? []).any((s) => s.name == 'Siegwerk')) {
        setState(() => _supplier = 'Siegwerk');
      }
    });

    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    var inks = items.where((i) => i.itemClass == InkItemClass.ink).toList();
    if (_shipment != null) {
      final codes = _shipment!.itemCodes.toSet();
      final filtered = inks.where((i) => codes.contains(i.itemCode)).toList();
      if (filtered.isNotEmpty) inks = filtered;
    }
    final shipments = ref.watch(inkOpenShipmentsProvider).valueOrNull ?? [];
    final suppliers = ref.watch(inkActiveSuppliersProvider).valueOrNull ?? [];
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    final totalKg = _rows.fold<double>(
        0, (s, r) => s + (double.tryParse(r.kgCtrl.text.trim()) ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Ink (IBC)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (shipments.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _shipment?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Shipment (optional)',
                  helperText: 'Validates IBCs against the packing list'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None — free text')),
                for (final s in shipments)
                  DropdownMenuItem(
                      value: s.id,
                      child: Text(
                          '${s.id}${s.containerNumber != null ? ' · ${s.containerNumber}' : ''}'
                          ' · ${s.expectedUnits.length} IBC')),
              ],
              onChanged: (id) {
                final match = shipments.where((s) => s.id == id).toList();
                _selectShipment(match.isEmpty ? null : match.first);
              },
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _supplier,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Supplier'),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderCtrl,
                  readOnly: _shipment != null,
                  decoration: InputDecoration(
                      labelText: 'Order number',
                      filled: _shipment != null,
                      isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cgnaCtrl,
                  readOnly: _shipment != null,
                  decoration: InputDecoration(
                      labelText: 'CGNA number',
                      filled: _shipment != null,
                      isDense: true),
                ),
              ),
            ],
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
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 8,
                      decoration: InputDecoration(
                          labelText: 'IBC number',
                          helperText: _rows[idx].charge != null
                              ? 'Charge ${_rows[idx].charge}'
                              : null,
                          counterText:
                              '${_rows[idx].numberCtrl.text.length}/8',
                          isDense: true),
                      onChanged: (_) => setState(() {}),
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
                                isDense: true),
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
                                isDense: true),
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
            onPressed: _submitting ? null : _confirmAndSubmit,
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
