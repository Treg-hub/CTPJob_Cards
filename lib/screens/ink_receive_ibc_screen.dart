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
  _IbcRow({
    String number = '',
    this.itemCode,
    String kg = '',
    this.charge,
    this.locked = false,
  })  : numberCtrl = TextEditingController(text: number),
        kgCtrl = TextEditingController(text: kg);

  final TextEditingController numberCtrl;
  String? itemCode;
  final TextEditingController kgCtrl;
  String? charge;
  bool locked;

  bool get hasContent =>
      numberCtrl.text.trim().isNotEmpty ||
      itemCode != null ||
      kgCtrl.text.trim().isNotEmpty;

  bool get isComplete {
    final numText = numberCtrl.text.trim();
    final kg = double.tryParse(kgCtrl.text.trim());
    return numText.length == 8 && itemCode != null && kg != null && kg > 0;
  }

  void dispose() {
    numberCtrl.dispose();
    kgCtrl.dispose();
  }
}

/// Phase 1b — Receive Ink via IBC. Scan (Code-128) or type each IBC's number,
/// pick the colour and enter kg. On submit each IBC is registered (audit) and
/// stock is raised as ONE cost-pending `purchase` per colour for the total kg
/// (e.g. 10 IBCs → 11,403 kg as a single receipt); a manager enters the cost later.
class InkReceiveIbcScreen extends ConsumerStatefulWidget {
  const InkReceiveIbcScreen({super.key, this.initialShipment});

  /// Shipment chosen on [InkSelectIbcShipmentScreen]; packing-list validation applies.
  final InkShipment? initialShipment;

  @override
  ConsumerState<InkReceiveIbcScreen> createState() => _State();
}

class _State extends ConsumerState<InkReceiveIbcScreen> {
  String? _supplier;
  final _orderCtrl = TextEditingController();
  final _cgnaCtrl = TextEditingController();
  DateTime _effectiveAt = DateTime.now();
  final List<_IbcRow> _rows = [];
  bool _submitting = false;
  late InkShipment? _shipment;

  @override
  void initState() {
    super.initState();
    _shipment = widget.initialShipment;
    if (_shipment != null) {
      _supplier = 'Siegwerk';
      _orderCtrl.text = _shipment!.orderNumber;
      _cgnaCtrl.text = _shipment!.cgnaNumber ?? '';
    }
  }

  Set<String> get _scannedIbcNumbers => {
        for (final r in _rows)
          if (r.numberCtrl.text.trim().length == 8) r.numberCtrl.text.trim(),
      };

  InkExpectedUnit? _expectedUnitFor(String ibcNumber) {
    if (_shipment == null) return null;
    for (final u in _shipment!.expectedUnits) {
      if (u.ibcNumber == ibcNumber) return u;
    }
    return null;
  }

  String _kgText(double kg) =>
      kg % 1 == 0 ? kg.toInt().toString() : kg.toString();

  void _applyScanResult(IbcScanResult res, {required bool lock}) {
    var itemCode = res.colour?.toLowerCase();
    var kg = res.weightKg == null
        ? ''
        : _kgText(res.weightKg!);
    final ibcNum = res.ibcNumber;

    if (ibcNum != null) {
      final expected = _expectedUnitFor(ibcNum);
      if (expected != null) {
        itemCode ??= expected.itemCode;
        if (kg.isEmpty && expected.netKg > 0) {
          kg = _kgText(expected.netKg);
        }
      }
    }

    setState(() {
      _rows.add(_IbcRow(
        number: ibcNum ?? '',
        itemCode: itemCode,
        kg: kg,
        charge: res.charge,
        locked: lock,
      ));
    });
  }

  Future<void> _scan() async {
    final res = await Navigator.push<IbcScanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => InkBarcodeScanScreen(
          existingIbcNumbers: _scannedIbcNumbers,
        ),
      ),
    );
    if (res == null || !res.hasAnything) return;
    _applyScanResult(res, lock: true);
  }

  Future<void> _editRow(_IbcRow row, {required bool isNew}) async {
    final items = ref.read(inkStockItemsProvider).valueOrNull ?? [];
    var inks = items.where((i) => i.itemClass == InkItemClass.ink).toList();
    if (_shipment != null) {
      final codes = _shipment!.itemCodes.toSet();
      final filtered = inks.where((i) => codes.contains(i.itemCode)).toList();
      if (filtered.isNotEmpty) inks = filtered;
    }
    final numberCtrl = TextEditingController(text: row.numberCtrl.text);
    String? itemCode = row.itemCode;
    final kgCtrl = TextEditingController(text: row.kgCtrl.text);
    var charge = row.charge;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              final duplicate = numberCtrl.text.trim().length == 8 &&
                  _scannedIbcNumbers.contains(numberCtrl.text.trim()) &&
                  numberCtrl.text.trim() != row.numberCtrl.text.trim();

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isNew ? 'Add IBC' : 'Edit IBC',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: 'IBC number',
                      helperText: charge != null ? 'Charge $charge' : null,
                      counterText: '${numberCtrl.text.length}/8',
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  if (duplicate)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'This IBC is already on the receipt.',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: itemCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Colour'),
                    items: [
                      for (final i in inks)
                        DropdownMenuItem(
                          value: i.itemCode,
                          child: Text(i.displayName),
                        ),
                    ],
                    onChanged: (v) => setSheetState(() => itemCode = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: kgCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'kg'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!isNew)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx, false);
                            setState(() {
                              row.dispose();
                              _rows.remove(row);
                            });
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: duplicate
                            ? null
                            : () => Navigator.pop(ctx, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (saved != true || !mounted) {
      if (isNew && !_rows.contains(row)) row.dispose();
      return;
    }

    final numText = numberCtrl.text.trim();
    final kg = double.tryParse(kgCtrl.text.trim());
    if (numText.length != 8 || itemCode == null || kg == null || kg <= 0) {
      if (isNew && !_rows.contains(row)) row.dispose();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid 8-digit IBC, colour and weight.'),
      ));
      return;
    }

    setState(() {
      row.numberCtrl.text = numText;
      row.itemCode = itemCode;
      row.kgCtrl.text = _kgText(kg);
      row.charge = charge;
      row.locked = true;
      if (isNew) _rows.add(row);
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _orderCtrl.dispose();
    _cgnaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
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
    final completeRows = _rows.where((r) => r.isComplete).toList();
    for (var i = 0; i < completeRows.length; i++) {
      final r = completeRows[i];
      final numText = r.numberCtrl.text.trim();
      final kg = double.parse(r.kgCtrl.text.trim());

      ibcs.add(InkIbc(
        ibcNumber: numText,
        itemCode: r.itemCode!,
        kg: kg,
        receivedDate: _effectiveAt,
        chargeNumber: r.charge,
      ));
    }
    if (ibcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Scan or add at least one complete IBC.'),
      ));
      return null;
    }
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

  ({List<MapEntry<String, ({int count, double kg})>> entries, double totalKg})
      _liveSummary(List<InkStockItem> items) {
    final summary = <String, ({int count, double kg})>{};
    for (final r in _rows.where((row) => row.isComplete)) {
      final code = r.itemCode!;
      final kg = double.parse(r.kgCtrl.text.trim());
      final prev = summary[code];
      summary[code] = prev == null
          ? (count: 1, kg: kg)
          : (count: prev.count + 1, kg: prev.kg + kg);
    }
    final orderOf = {for (final i in items) i.itemCode: i.displayOrder};
    final entries = summary.entries.toList()
      ..sort((a, b) =>
          (orderOf[a.key] ?? 9999).compareTo(orderOf[b.key] ?? 9999));
    final totalKg =
        entries.fold<double>(0, (s, e) => s + e.value.kg);
    return (entries: entries, totalKg: totalKg);
  }

  Future<void> _confirmAndSubmit() async {
    final ibcs = _buildValidIbcs();
    if (ibcs == null) return;

    final items = ref.read(inkStockItemsProvider).valueOrNull ?? [];
    final displayName = {for (final i in items) i.itemCode: i.displayName};
    final live = _liveSummary(items);
    final nf = NumberFormat('#,##0.##');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Colour',
                      style: Theme.of(ctx)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      'IBCs',
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Text(
                      'Total kg',
                      textAlign: TextAlign.right,
                      style: Theme.of(ctx)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            for (final entry in live.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(displayName[entry.key] ?? entry.key),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${entry.value.count}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 76,
                      child: Text(
                        nf.format(entry.value.kg),
                        textAlign: TextAlign.right,
                      ),
                    ),
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
                  child: Text(
                    'Total',
                    style: Theme.of(ctx)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${ibcs.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: Text(
                    nf.format(live.totalKg),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Receive IBCs'),
          ),
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
        content: Text('${ibcs.length} IBC(s) received — cost pending.'),
      ));
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
    final displayName = {for (final i in items) i.itemCode: i.displayName};
    final suppliers = ref.watch(inkActiveSuppliersProvider).valueOrNull ?? [];
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    final nf = NumberFormat('#,##0.##');
    final live = _liveSummary(items);
    final completeCount = _rows.where((r) => r.isComplete).length;
    final scheme = Theme.of(context).colorScheme;
    final expectedCount = _shipment?.expectedUnits.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Ink (IBC)'),
        actions: [
          IconButton(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan IBC',
          ),
        ],
      ),
      body: Column(
        children: [
          if (completeCount > 0)
            Material(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Captured',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                        const Spacer(),
                        Text(
                          '$completeCount IBC${completeCount == 1 ? '' : 's'}'
                          ' · ${nf.format(live.totalKg)} kg',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    if (live.entries.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final e in live.entries)
                        Text(
                          '${displayName[e.key] ?? e.key}: '
                          '${e.value.count} × ${nf.format(e.value.kg)} kg',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                    ],
                    if (expectedCount != null && expectedCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Shipment progress: $completeCount / $expectedCount',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_shipment != null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(_shipment!.id),
                      subtitle: Text(
                        [
                          'Order ${_shipment!.orderNumber}',
                          if (_shipment!.containerNumber != null)
                            'Container ${_shipment!.containerNumber}',
                          if (expectedCount != null)
                            '$expectedCount IBCs on packing list',
                        ].join(' · '),
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _supplier,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier'),
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
                    alignment: Alignment.centerLeft,
                  ),
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
                          isDense: true,
                        ),
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
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'IBCs',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      completeCount == 0
                          ? 'Tap scan or add'
                          : '$completeCount captured',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_rows.where((r) => r.isComplete).isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Scan IBC labels with the button above. '
                      'Captured rows lock to prevent accidental edits.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final row in _rows.where((r) => r.isComplete))
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(
                        row.locked ? Icons.lock_outline : Icons.edit_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        row.numberCtrl.text,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          displayName[row.itemCode] ?? row.itemCode ?? '?',
                          '${nf.format(double.parse(row.kgCtrl.text.trim()))} kg',
                          if (row.charge != null) 'Charge ${row.charge}',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => _editRow(row, isNew: false),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _editRow(_IbcRow(), isNew: true),
                  icon: const Icon(Icons.add),
                  label: const Text('Add IBC manually'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _submitting || completeCount == 0 ? null : _confirmAndSubmit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Receive IBCs'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}