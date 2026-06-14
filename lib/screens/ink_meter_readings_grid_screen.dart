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

/// Phase 2 — Meter Readings (grid). Same cumulative entry as the standard meter
/// screen, but each meter shows its previous readings for quick context/easier
/// entry. Includes meter-reset handling and an editable date+time.
class InkMeterReadingsGridScreen extends ConsumerStatefulWidget {
  const InkMeterReadingsGridScreen({super.key});

  @override
  ConsumerState<InkMeterReadingsGridScreen> createState() => _State();
}

class _State extends ConsumerState<InkMeterReadingsGridScreen> {
  final _ctrls = <String, TextEditingController>{};
  final _reset = <String, bool>{};
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  TextEditingController _ctrl(String code) =>
      _ctrls.putIfAbsent(code, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit(List<InkStockItem> items, Map<String, double> factors,
      Map<String, double> last) async {
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    final sessionId = const Uuid().v4();
    final toWrite = <InkTransaction>[];
    final problems = <String>[];
    for (final item in items) {
      final raw = _ctrl(item.itemCode).text.trim();
      if (raw.isEmpty) continue;
      final entered = double.tryParse(raw);
      if (entered == null) {
        problems.add('${item.displayName}: invalid number');
        continue;
      }
      final factor = factors[item.itemCode] ?? 0;
      final lastReading = last[item.itemCode];
      double litres;
      if (lastReading == null) {
        litres = 0;
      } else if (_reset[item.itemCode] == true) {
        litres = entered;
      } else {
        litres = entered - lastReading;
        if (litres < 0) {
          problems.add('${item.displayName}: reading below last — tick "meter was reset"');
          continue;
        }
      }
      toWrite.add(InkTransaction(
        type: InkTxnType.consumptionMeter,
        stockItemCode: item.itemCode,
        quantityDelta: -(litres * factor),
        effectiveAt: _effectiveAt,
        readingDate: _effectiveAt,
        costStatus: InkCostStatus.na,
        litresEntered: litres,
        conversionFactorUsed: factor,
        meterReading: entered,
        sessionId: sessionId,
        actorClockNo: emp?.clockNo ?? '',
        actorName: emp?.name ?? '',
        idempotencyKey: const Uuid().v4(),
      ));
    }
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(problems.join('\n')),
          backgroundColor: Theme.of(context).colorScheme.error));
      return;
    }
    if (toWrite.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter at least one reading.')));
      return;
    }
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final svc = ref.read(inkServiceProvider);
    try {
      for (final t in toWrite) {
        await svc.recordTransaction(t);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${toWrite.length} reading(s) recorded.')));
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
    final factorsMap = ref.watch(inkConversionFactorsProvider).valueOrNull ?? {};
    final factors = {
      for (final e in factorsMap.entries)
        if (e.value.active && e.value.kgPerLitre > 0) e.key: e.value.kgPerLitre
    };
    final last = ref.watch(inkLatestMeterReadingsProvider).valueOrNull ?? {};
    final recent = ref.watch(inkRecentMeterReadingsProvider).valueOrNull ?? {};
    final meterItems = items
        .where((i) => i.metered && factors.containsKey(i.itemCode))
        .toList();
    final df = DateFormat('EEE d MMM HH:mm');

    if (meterItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meter Readings (grid)')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('No metered items. A manager must set conversion '
                  'factors (Ink hub → Conversion Factors).')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meter Readings (grid)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text('Reading date: ${df.format(_effectiveAt)}'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: Alignment.centerLeft),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final item in meterItems)
                  _GridCard(
                    item: item,
                    controller: _ctrl(item.itemCode),
                    factor: factors[item.itemCode]!,
                    last: last[item.itemCode],
                    history: recent[item.itemCode] ?? const [],
                    reset: _reset[item.itemCode] ?? false,
                    onResetChanged: (v) =>
                        setState(() => _reset[item.itemCode] = v),
                    onChanged: () => setState(() {}),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      _submitting ? null : () => _submit(meterItems, factors, last),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Record readings'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.item,
    required this.controller,
    required this.factor,
    required this.last,
    required this.history,
    required this.reset,
    required this.onResetChanged,
    required this.onChanged,
  });

  final InkStockItem item;
  final TextEditingController controller;
  final double factor;
  final double? last;
  final List<({DateTime at, double reading})> history;
  final bool reset;
  final ValueChanged<bool> onResetChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final qty = NumberFormat('#,##0.##');
    final hd = DateFormat('d/M');
    final scheme = Theme.of(context).colorScheme;
    final entered = double.tryParse(controller.text.trim());
    final belowLast = last != null && entered != null && entered < last!;
    final showReset = last != null && (belowLast || reset);

    String preview = '';
    Color? color;
    if (entered != null) {
      if (last == null) {
        preview = 'First reading — sets baseline';
        color = scheme.onSurfaceVariant;
      } else if (reset) {
        preview =
            'Reset — ${qty.format(entered)} L → ${qty.format(entered * factor)} kg';
      } else if (belowLast) {
        preview = 'Below last (${qty.format(last)}). Was the meter reset?';
        color = scheme.error;
      } else {
        final d = entered - last!;
        preview = '${qty.format(d)} L → ${qty.format(d * factor)} kg';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.displayName,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            // Previous readings strip (newest → oldest).
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final h in history)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          Text(hd.format(h.at),
                              style: Theme.of(context).textTheme.labelSmall),
                          Text(qty.format(h.reading),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ),
                  if (history.isEmpty)
                    Text('No previous readings',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'New meter reading',
                suffixText: 'L',
                isDense: true,
              ),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(preview,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: color)),
            ],
            if (showReset)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title:
                    const Text('Meter was reset (use new reading as consumption)'),
                value: reset,
                onChanged: (v) => onResetChanged(v ?? false),
              ),
          ],
        ),
      ),
    );
  }
}
