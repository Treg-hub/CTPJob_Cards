import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/ink_purchase_order.dart';
import '../utils/ink_po_fulfillment.dart';
import '../models/ink_shipment.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_delivery_note_flow.dart';
import '../utils/ink_period_guard.dart';
import '../utils/persona_audit.dart';
import '../utils/ink_pickers.dart';
import '../utils/screen_insets.dart';
import '../widgets/ink_guide_banner.dart';

/// Receive raw material / solvent.
///
/// **Against a local PO** ([initialPurchaseOrder]): multi-line confirm — enter
/// qty received per open line, one submit writes purchase txns + CF PO
/// remaining (mirrors IBC shipment pick → receive).
///
/// **Against a pallet import shipment** ([initialShipment]): multi-line qty
/// per invoice line; stamps `shipment_id` on purchases + shipment
/// `received_units` (aggregate).
///
/// **Ad-hoc** (no order): free-form single item + supplier (escape hatch).
///
/// Cost is always `pending` — manager enters total cost later on Pulse.
class InkReceiveRawMaterialScreen extends ConsumerStatefulWidget {
  const InkReceiveRawMaterialScreen({
    super.key,
    this.initialPurchaseOrder,
    this.initialShipment,
  });

  /// Order chosen on [InkSelectLocalOrderScreen].
  final InkPurchaseOrder? initialPurchaseOrder;

  /// Pallet import shipment chosen on [InkSelectIbcShipmentScreen].
  final InkShipment? initialShipment;

  @override
  ConsumerState<InkReceiveRawMaterialScreen> createState() =>
      _InkReceiveRawMaterialScreenState();
}

class _InkReceiveRawMaterialScreenState
    extends ConsumerState<InkReceiveRawMaterialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final Map<String, TextEditingController> _lineQtyCtrls = {};
  String? _itemCode;
  String? _supplier;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;
  late final InkPurchaseOrder? _purchaseOrder;
  late final InkShipment? _shipment;

  bool get _againstPo => _purchaseOrder != null;
  bool get _againstShipment => _shipment != null && !_againstPo;

  @override
  void initState() {
    super.initState();
    _purchaseOrder = widget.initialPurchaseOrder;
    _shipment = widget.initialShipment;
    if (_purchaseOrder != null) {
      _supplier = _purchaseOrder!.supplierName;
      for (final open in _purchaseOrder!.openLines) {
        _lineQtyCtrls[open.line.itemCode] = TextEditingController();
      }
    } else if (_shipment != null) {
      _supplier = 'Siegwerk';
      for (final line in _shipment!.lines) {
        if (line.itemCode.isEmpty) continue;
        _lineQtyCtrls.putIfAbsent(
          line.itemCode,
          () => TextEditingController(),
        );
      }
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _qtyCtrl.dispose();
    for (final c in _lineQtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  List<({String itemCode, double qty, String unit, String displayName})>
      _parseLineQtys() {
    final out =
        <({String itemCode, double qty, String unit, String displayName})>[];
    if (_againstPo) {
      final po = _purchaseOrder!;
      for (final open in po.openLines) {
        final raw = _lineQtyCtrls[open.line.itemCode]?.text.trim() ?? '';
        if (raw.isEmpty) continue;
        final qty = double.tryParse(raw);
        if (qty == null || qty <= 0) continue;
        out.add((
          itemCode: open.line.itemCode,
          qty: qty,
          unit: open.line.unit,
          displayName: open.line.displayName,
        ));
      }
      return out;
    }
    if (_againstShipment) {
      final s = _shipment!;
      for (final line in s.lines) {
        if (line.itemCode.isEmpty) continue;
        final raw = _lineQtyCtrls[line.itemCode]?.text.trim() ?? '';
        if (raw.isEmpty) continue;
        final qty = double.tryParse(raw);
        if (qty == null || qty <= 0) continue;
        final name = (line.description ?? '').trim().isNotEmpty
            ? line.description!.trim()
            : line.itemCode;
        out.add((
          itemCode: line.itemCode,
          qty: qty,
          unit: 'KG',
          displayName: name,
        ));
      }
    }
    return out;
  }

  Future<void> _submitMultiLine({
    required String? supplierName,
    String? purchaseOrderId,
    String? shipmentId,
  }) async {
    if (!guardPersonaSubmit(context)) return;
    final lines = _parseLineQtys();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter quantity received for at least one line'),
      ));
      return;
    }
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;

    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    final service = ref.read(inkServiceProvider);

    var recorded = 0;
    Object? lastError;
    Map<String, dynamic> lastPoResult = const {};
    for (final line in lines) {
      final txn = InkTransaction(
        type: InkTxnType.purchase,
        stockItemCode: line.itemCode,
        quantityDelta: line.qty,
        effectiveAt: _effectiveAt,
        costStatus: InkCostStatus.pending,
        supplierName: supplierName,
        actorClockNo: emp?.clockNo ?? '',
        actorName: emp?.name ?? '',
        idempotencyKey: const Uuid().v4(),
        notes: notes,
        purchaseOrderId: purchaseOrderId,
        shipmentId: shipmentId,
      );
      try {
        lastPoResult = await service.recordRawMaterialReceipt(
          txn: txn,
          purchaseOrderId: purchaseOrderId,
          shipmentId: shipmentId,
        );
        recorded++;
      } catch (e) {
        lastError = e;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          recorded == 0
              ? 'Failed to record: $lastError'
              : 'Recorded $recorded of ${lines.length} lines, then failed: $lastError. '
                  'Re-open to finish remaining lines.',
        ),
      ));
      if (recorded > 0) {
        invalidateInkReceivedPeriodLists(ref);
        Navigator.pop(context);
      }
      return;
    }
    final n = lines.length;
    final message = _receiptSuccessMessage(
      lineCount: n,
      againstPo: purchaseOrderId != null && purchaseOrderId.isNotEmpty,
      poResult: lastPoResult,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    invalidateInkReceivedPeriodLists(ref);
    Navigator.pop(context);
  }

  String _receiptSuccessMessage({
    required int lineCount,
    required bool againstPo,
    required Map<String, dynamic> poResult,
  }) {
    if (!againstPo || poResult.isEmpty) {
      return lineCount == 1
          ? 'Receipt saved — marked received.'
          : '$lineCount line receipts saved — marked received.';
    }
    final status = poResult['status'] as String? ?? '';
    final autoOff = poResult['auto_write_off_kg_by_item'];
    var autoTotal = 0.0;
    if (autoOff is Map) {
      for (final v in autoOff.values) {
        if (v is num) autoTotal += v.toDouble();
      }
    }
    final remaining = poResult['remaining_kg_by_item'];
    var openTotal = 0.0;
    if (remaining is Map) {
      for (final v in remaining.values) {
        if (v is num) openTotal += v.toDouble();
      }
    }
    final base = lineCount == 1
        ? 'Receipt saved'
        : '$lineCount line receipts saved';
    if (status == 'fulfilled' && autoTotal > inkPoFulfilledThreshold) {
      return '$base — order closed (small shortfall auto-accepted ≤1%).';
    }
    if (status == 'fulfilled') {
      return '$base — order fully received.';
    }
    if (openTotal > inkPoFulfilledThreshold) {
      return '$base — residual left open. If no further delivery, a manager '
          'must finalize the order on Pulse.';
    }
    return '$base — marked received.';
  }

  /// Live helper under each line qty field (preview of auto vs manager residual).
  String? _varianceHelper({
    required double remaining,
    required double ordered,
    required String unit,
    TextEditingController? ctrl,
  }) {
    final raw = ctrl?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    final qty = double.tryParse(raw);
    if (qty == null || qty <= 0) return null;
    final residual = residualAfterReceipt(
      remainingBefore: remaining,
      quantityReceived: qty,
    );
    if (residual <= inkPoFulfilledThreshold) {
      return 'Matches remaining — line will close.';
    }
    final ord = ordered > 0 ? ordered : remaining;
    final pct = ord > 0 ? (residual / ord) * 100 : 0.0;
    final qtyFmt = NumberFormat('#,##0.##');
    if (residualWithinAutoVariance(residual: residual, ordered: ord)) {
      return 'Short ${qtyFmt.format(residual)} $unit '
          '(${pct.toStringAsFixed(2)}%) — within 1%; order can auto-close.';
    }
    return 'Short ${qtyFmt.format(residual)} $unit '
        '(${pct.toStringAsFixed(1)}%) — stays open; manager finalize if no more delivery.';
  }

  Future<void> _submitAgainstPo() => _submitMultiLine(
        supplierName: _purchaseOrder!.supplierName,
        purchaseOrderId: _purchaseOrder!.id,
      );

  Future<void> _submitAgainstShipment() => _submitMultiLine(
        supplierName: _supplier ?? 'Siegwerk',
        shipmentId: _shipment!.id,
      );

  Future<void> _submitAdHoc() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_itemCode == null || _supplier == null) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
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
    );
    try {
      await ref.read(inkServiceProvider).recordRawMaterialReceipt(txn: txn);
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
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    final qtyFmt = NumberFormat('#,##0.##');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _againstPo
              ? 'Confirm receipt'
              : _againstShipment
                  ? 'Receive pallet shipment'
                  : 'Exception: receive without order',
        ),
      ),
      body: _againstPo
          ? _buildAgainstPo(context, df, qtyFmt)
          : _againstShipment
              ? _buildAgainstShipment(context, df, qtyFmt)
              : _buildAdHoc(context, df),
    );
  }

  Widget _buildAgainstShipment(
    BuildContext context,
    DateFormat df,
    NumberFormat qtyFmt,
  ) {
    final s = _shipment!;
    final scheme = Theme.of(context).colorScheme;
    final lines = s.lines.where((l) => l.itemCode.isNotEmpty).toList();

    return ListView(
      padding: ScreenInsets.symmetricScroll(context),
      children: [
        const InkGuideBanner.receiveLocalConfirm(),
        const SizedBox(height: 12),
        Card(
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.id,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Order ${s.orderNumber}'
                  '${s.cgnaNumber != null ? ' · CGNA ${s.cgnaNumber}' : ''}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (s.expectedArrival != null)
                  Text(
                    'ETA ${DateFormat('d MMM yyyy').format(s.expectedArrival!.toLocal())} (est.)',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Qty received (kg)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final line in lines) ...[
          Text(
            (line.description ?? '').trim().isNotEmpty
                ? '${line.description} (${line.itemCode})'
                : line.itemCode,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            'Expected ${qtyFmt.format(line.expectedKg)} kg',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _lineQtyCtrls[line.itemCode],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 12),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Effective at'),
          subtitle: Text(df.format(_effectiveAt)),
          trailing: const Icon(Icons.event),
          onTap: _pickDate,
        ),
        TextField(
          controller: _notesCtrl,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _submitting ? null : _submitAgainstShipment,
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save receipt'),
        ),
      ],
    );
  }

  Widget _buildAgainstPo(
    BuildContext context,
    DateFormat df,
    NumberFormat qtyFmt,
  ) {
    final po = _purchaseOrder!;
    final open = po.openLines;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: ScreenInsets.symmetricScroll(context),
      children: [
        const InkGuideBanner.receiveLocalConfirm(),
        const SizedBox(height: 12),
        Card(
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  po.pulseRef,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(po.supplierName),
                if (po.erpOrderNumber != null &&
                    po.erpOrderNumber!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pastel order ${po.erpOrderNumber}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (po.pastelRfoNumber != null &&
                    po.pastelRfoNumber!.isNotEmpty)
                  Text(
                    'Pastel RFO ${po.pastelRfoNumber}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Enter quantity received for each line. Leave blank if not on this delivery.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        if (open.isEmpty)
          const Text('No open remaining qty on this order.')
        else
          for (final e in open) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.line.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Remaining on order: ${qtyFmt.format(e.remaining)} ${e.line.unit}'
                      '${e.line.finalKg > 0 ? ' · ordered ${qtyFmt.format(e.line.finalKg)} ${e.line.unit}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lineQtyCtrls[e.line.itemCode],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Quantity received',
                        suffixText: e.line.unit,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: _varianceHelper(
                          remaining: e.remaining,
                          ordered: e.line.finalKg > 0
                              ? e.line.finalKg
                              : e.remaining,
                          unit: e.line.unit,
                          ctrl: _lineQtyCtrls[e.line.itemCode],
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
          ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.event),
          label: Text('Effective date: ${df.format(_effectiveAt)}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.centerLeft,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesCtrl,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Card(
          color: scheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Partial receives are OK. Shortfall ≤1% of ordered auto-closes '
                  'the line (delivery variance). Larger shortfalls stay open — '
                  'receive the rest later or a manager finalizes on Pulse. '
                  'Cost is entered by a manager later.',
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _submitting ? null : _submitAgainstPo,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Confirm receipt'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }

  Widget _buildAdHoc(BuildContext context, DateFormat df) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final suppliersAsync = ref.watch(inkActiveSuppliersProvider);

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (allItems) {
        final items = allItems
            .where((i) =>
                i.itemClass == InkItemClass.raw ||
                i.itemClass == InkItemClass.solvent)
            .toList();
        InkStockItem? selected;
        for (final i in items) {
          if (i.itemCode == _itemCode) selected = i;
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: ScreenInsets.symmetricScroll(context),
            children: [
              const InkGuideBanner.receiveLocalAdHoc(),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _itemCode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Item'),
                items: [
                  for (final i in items)
                    DropdownMenuItem(
                      value: i.itemCode,
                      child: Text('${i.displayName} (${i.unit})'),
                    ),
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
              const SizedBox(height: 12),
              suppliersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Suppliers error: $e'),
                data: (suppliers) => DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _supplier,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier'),
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
                  alignment: Alignment.centerLeft,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
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
                        'when the cost is captured.',
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submitAdHoc,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Record receipt'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
