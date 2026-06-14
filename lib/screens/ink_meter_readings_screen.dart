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

/// Phase 1d — Meter Readings (Lurgi ink/binder consumption).
///
/// Rebuilt for the factory floor: a single vertical scroll, one card per meter,
/// 48dp touch targets (the old build crammed 5 columns with 20dp buttons).
/// Readings are entered in LITRES and converted to kg via the item's factor.
/// Two modes: CUMULATIVE (delta = new − last reading) and DIRECT (enter the
/// consumed litres, e.g. when the meter is unavailable — the "manual reading").
class InkMeterReadingsScreen extends ConsumerStatefulWidget {
  const InkMeterReadingsScreen({super.key});

  @override
  ConsumerState<InkMeterReadingsScreen> createState() => _State();
}

class _State extends ConsumerState<InkMeterReadingsScreen> {
  static final _qty = NumberFormat('#,##0.##');
  final _ctrls = <String, TextEditingController>{};
  final _reset = <String, bool>{}; // per-item: meter was reset
  bool _cumulative = true;
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

  Future<void> _submit(
    List<InkStockItem> meterItems,
    Map<String, double> factors,
    Map<String, double> lastReadings,
  ) async {
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    final sessionId = const Uuid().v4();
    final toWrite = <InkTransaction>[];
    final problems = <String>[];

    for (final item in meterItems) {
      final raw = _ctrl(item.itemCode).text.trim();
      if (raw.isEmpty) continue;
      final entered = double.tryParse(raw);
      if (entered == null) {
        problems.add('${item.displayName}: invalid number');
        continue;
      }
      final factor = factors[item.itemCode] ?? 0;
      final last = lastReadings[item.itemCode];
      double litres;
      double? cumulative;
      if (_cumulative) {
        cumulative = entered;
        if (last == null) {
          // First reading establishes a baseline — record it with no consumption.
          litres = 0;
        } else if (_reset[item.itemCode] == true) {
          // Meter was reset → the new reading IS the consumption since the reset.
          litres = entered;
        } else {
          litres = entered - last;
          if (litres < 0) {
            problems.add('${item.displayName}: reading ${_qty.format(entered)} is below '
                'last ${_qty.format(last)} — tick "meter was reset" if that is correct');
            continue;
          }
        }
      } else {
        litres = entered;
      }
      final kg = litres * factor;
      toWrite.add(InkTransaction(
        type: InkTxnType.consumptionMeter,
        stockItemCode: item.itemCode,
        quantityDelta: -kg,
        effectiveAt: _effectiveAt,
        readingDate: _effectiveAt,
        costStatus: InkCostStatus.na,
        litresEntered: litres,
        conversionFactorUsed: factor,
        meterReading: cumulative,
        sessionId: sessionId,
        actorClockNo: emp?.clockNo ?? '',
        actorName: emp?.name ?? '',
        idempotencyKey: const Uuid().v4(),
      ));
    }

    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(problems.join('\n')), backgroundColor: Theme.of(context).colorScheme.error));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${toWrite.length} reading(s) recorded.')));
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
    final factorsAsync = ref.watch(inkConversionFactorsProvider);
    final lastAsync = ref.watch(inkLatestMeterReadingsProvider);
    final df = DateFormat('EEE d MMM yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Meter Readings')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          final factorsMap = factorsAsync.valueOrNull ?? {};
          final factors = {
            for (final e in factorsMap.entries)
              if (e.value.active && e.value.kgPerLitre > 0)
                e.key: e.value.kgPerLitre
          };
          final last = lastAsync.valueOrNull ?? {};
          final meterItems = items
              .where((i) => i.metered && factors.containsKey(i.itemCode))
              .toList();

          if (meterItems.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text(
                      'No metered items yet. A manager must set conversion '
                      'factors (Ink hub → Conversion Factors).')),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Cumulative')),
                          ButtonSegment(value: false, label: Text('Direct')),
                        ],
                        selected: {_cumulative},
                        onSelectionChanged: (s) =>
                            setState(() => _cumulative = s.first),
                      ),
                    ),
                  ],
                ),
              ),
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
                      _MeterCard(
                        item: item,
                        controller: _ctrl(item.itemCode),
                        cumulative: _cumulative,
                        factor: factors[item.itemCode]!,
                        last: last[item.itemCode],
                        reset: _reset[item.itemCode] ?? false,
                        onResetChanged: (v) =>
                            setState(() => _reset[item.itemCode] = v),
                        onChanged: () => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _submit(meterItems, factors, last),
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
          );
        },
      ),
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({
    required this.item,
    required this.controller,
    required this.cumulative,
    required this.factor,
    required this.last,
    required this.reset,
    required this.onResetChanged,
    required this.onChanged,
  });

  final InkStockItem item;
  final TextEditingController controller;
  final bool cumulative;
  final double factor;
  final double? last;
  final bool reset;
  final ValueChanged<bool> onResetChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final qty = NumberFormat('#,##0.##');
    final scheme = Theme.of(context).colorScheme;
    final entered = double.tryParse(controller.text.trim());
    final belowLast =
        cumulative && last != null && entered != null && entered < last!;
    final showReset = cumulative && last != null && (belowLast || reset);

    String preview = '';
    Color? previewColor;
    if (entered != null) {
      if (cumulative) {
        if (last == null) {
          preview = 'First reading — sets baseline, no consumption';
          previewColor = scheme.onSurfaceVariant;
        } else if (reset) {
          preview =
              'Reset — ${qty.format(entered)} L → ${qty.format(entered * factor)} kg consumed';
        } else if (belowLast) {
          preview =
              'Reading is below last (${qty.format(last)}). Was the meter reset?';
          previewColor = scheme.error;
        } else {
          final d = entered - last!;
          preview = '${qty.format(d)} L → ${qty.format(d * factor)} kg';
        }
      } else {
        preview = '${qty.format(entered * factor)} kg';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.displayName,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (cumulative && last != null)
                  Text('Last: ${qty.format(last)} L',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: cumulative ? 'New meter reading' : 'Consumed',
                suffixText: 'L',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(preview,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: previewColor)),
            ],
            if (showReset)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Meter was reset (use new reading as consumption)'),
                value: reset,
                onChanged: (v) => onResetChanged(v ?? false),
              ),
          ],
        ),
      ),
    );
  }
}
