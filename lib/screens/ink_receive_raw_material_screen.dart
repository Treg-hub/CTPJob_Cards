import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/ink_shipment.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';

/// Phase 1a — Receive Raw Material / Solvent.
///
/// Operator records an incoming delivery of a raw material or toloul as a
/// `purchase` transaction. Quantity only — the COST is deferred: the receipt is
/// captured `cost_status: pending` and a manager enters the total cost later
/// (which triggers the WAC re-replay). Inks are received separately via the IBC
/// flow (Phase 1b). The operator may set the effective date (backdating is
/// supported by the ledger).
class InkReceiveRawMaterialScreen extends ConsumerStatefulWidget {
  const InkReceiveRawMaterialScreen({super.key});

  @override
  ConsumerState<InkReceiveRawMaterialScreen> createState() =>
      _InkReceiveRawMaterialScreenState();
}

class _InkReceiveRawMaterialScreenState
    extends ConsumerState<InkReceiveRawMaterialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _itemCode;
  String? _supplier;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  /// When set, receiving against this Pulse-created pallet shipment: supplier
  /// is Siegwerk and the item list is restricted to its lines.
  InkShipment? _shipment;

  void _selectShipment(InkShipment? s) {
    setState(() {
      _shipment = s;
      if (s != null) {
        _supplier = 'Siegwerk';
        if (_itemCode != null && !s.itemCodes.contains(_itemCode)) {
          _itemCode = null;
        }
      }
    });
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_itemCode == null || _supplier == null) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    final txn = InkTransaction(
      type: InkTxnType.purchase,
      stockItemCode: _itemCode!,
      quantityDelta: double.parse(_qtyCtrl.text.trim()),
      effectiveAt: _effectiveAt,
      costStatus: InkCostStatus.pending,
      supplierName: _supplier,
      actorClockNo: emp?.clockNo ?? '',
      actorName: emp?.name ?? '',
      idempotencyKey: const Uuid().v4(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      shipmentId: _shipment?.id,
    );
    try {
      await ref
          .read(inkServiceProvider)
          .recordRawMaterialReceipt(txn: txn, shipmentId: _shipment?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Receipt recorded — cost pending manager entry.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to record: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final suppliersAsync = ref.watch(inkActiveSuppliersProvider);
    final df = DateFormat('EEE d MMM yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Raw Material')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allItems) {
          var items = allItems
              .where((i) =>
                  i.itemClass == InkItemClass.raw ||
                  i.itemClass == InkItemClass.solvent)
              .toList();
          if (_shipment != null) {
            final codes = _shipment!.itemCodes.toSet();
            final filtered =
                items.where((i) => codes.contains(i.itemCode)).toList();
            if (filtered.isNotEmpty) items = filtered;
          }
          InkStockItem? selected;
          for (final i in items) {
            if (i.itemCode == _itemCode) selected = i;
          }
          double? expectedKg;
          if (_shipment != null) {
            for (final l in _shipment!.lines) {
              if (l.itemCode == _itemCode) {
                expectedKg = l.expectedKg;
                break;
              }
            }
          }
          final shipments =
              ref.watch(inkOpenPalletShipmentsProvider).valueOrNull ?? [];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (shipments.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _shipment?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Shipment (optional)',
                        helperText: 'Link this receipt to a pallet shipment'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('None — free text')),
                      for (final s in shipments)
                        DropdownMenuItem(
                            value: s.id,
                            child: Text(s.containerNumber != null
                                ? '${s.id} · ${s.containerNumber}'
                                : s.id)),
                    ],
                    onChanged: (id) {
                      final match =
                          shipments.where((s) => s.id == id).toList();
                      _selectShipment(match.isEmpty ? null : match.first);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quantity received',
                    suffixText: selected?.unit ?? '',
                  ),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim());
                    if (d == null || d <= 0) {
                      return 'Enter a quantity greater than 0';
                    }
                    return null;
                  },
                ),
                if (expectedKg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Expected on shipment: '
                      '${NumberFormat('#,##0.##').format(expectedKg)} '
                      '${selected?.unit ?? 'KG'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                suppliersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Suppliers error: $e'),
                  data: (suppliers) => DropdownButtonFormField<String>(
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
                    validator: (v) => v == null ? 'Select a supplier' : null,
                  ),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Cost is entered by a manager once the supplier '
                              'documents arrive. Stock goes up now; WAC updates '
                              'when the cost is captured.')),
                    ]),
                  ),
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
                  label: const Text('Record receipt'),
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
