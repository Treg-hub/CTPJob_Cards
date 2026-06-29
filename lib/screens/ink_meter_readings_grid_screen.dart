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
import '../utils/role.dart' as role_utils;

/// Maximum expected daily consumption in litres, matched against the item's
/// displayName/itemCode (case-insensitive substring). Values set by factory
/// management. Items not listed have no limit check.
const _maxConsumptionByKeyword = <String, double>{
  'black': 1500,
  'blue': 1500,
  'red': 2000,
  'yellow': 3200,
  'binder': 3000,
  'gravure': 3000,
};

double? _maxLitresFor(InkStockItem item) {
  final search = '${item.itemCode} ${item.displayName}'.toLowerCase();
  for (final e in _maxConsumptionByKeyword.entries) {
    if (search.contains(e.key)) return e.value;
  }
  return null;
}

/// Primary meter readings screen — cumulative entry with history strip per
/// meter for quick context. Replaces the legacy list-style screen.
/// Date/time can only be edited by managers and admins; Lurgi users see
/// the date as read-only text.
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
          problems.add(
              '${item.displayName}: reading below last — tick "meter was reset"');
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
        idempotencyKey: '${sessionId}_${item.itemCode}',
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

    // Warn when any consumption exceeds the per-item expected maximum.
    final qty = NumberFormat('#,##0.##');
    final warnings = <String>[];
    for (final item in items) {
      final raw = _ctrl(item.itemCode).text.trim();
      final entered = double.tryParse(raw);
      if (entered == null) continue;
      final maxL = _maxLitresFor(item);
      if (maxL == null) continue;
      final lastReading = last[item.itemCode];
      double? consumption;
      if (lastReading == null) {
        // baseline — no consumption recorded
      } else if (_reset[item.itemCode] == true) {
        consumption = entered;
      } else if (entered >= lastReading) {
        consumption = entered - lastReading;
      }
      if (consumption != null && consumption > maxL) {
        warnings.add(
            '${item.displayName}: ${qty.format(consumption)} L (max ${qty.format(maxL)} L)');
      }
    }
    if (warnings.isNotEmpty) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Above expected maximum'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The following readings exceed the daily limit:'),
              const SizedBox(height: 10),
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: Theme.of(ctx).colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w)),
                  ]),
                ),
              const SizedBox(height: 10),
              const Text('Verify the readings are correct before proceeding.'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Review')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm & Submit')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (!mounted) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;

    setState(() => _submitting = true);
    final svc = ref.read(inkServiceProvider);
    try {
      await svc.recordDailyMeterSession(
        sessionId: sessionId,
        readingDate: _effectiveAt,
        inkTransactions: toWrite,
        toloulLines: const [],
        actorClockNo: emp?.clockNo ?? '',
        actorName: emp?.name ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${toWrite.length} reading(s) recorded.')));
      Navigator.pop(context);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final isDuplicateDay = e.message.contains('calendar day');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isDuplicateDay
            ? 'Meter readings already submitted for this day. '
                'Void the existing session first (Ink hub → Meter Sessions).'
            : e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final canEditDate = role_utils.isInkManager(emp) || role_utils.isAdmin(emp);

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
        appBar: AppBar(title: const Text('Meter Readings')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('No metered items. A manager must set conversion '
                  'factors (Ink hub → Conversion Factors).')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meter Readings')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: canEditDate
                ? OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text('Reading date: ${df.format(_effectiveAt)}'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        alignment: Alignment.centerLeft),
                  )
                : Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text('Reading date: ${df.format(_effectiveAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
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
                    maxConsumptionLitres: _maxLitresFor(item),
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
    this.maxConsumptionLitres,
  });

  final InkStockItem item;
  final TextEditingController controller;
  final double factor;
  final double? last;
  final List<({DateTime at, double reading})> history;
  final bool reset;
  final double? maxConsumptionLitres;
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
    double? consumptionLitres;
    if (entered != null) {
      if (last == null) {
        preview = 'First reading — sets baseline';
        color = scheme.onSurfaceVariant;
      } else if (reset) {
        consumptionLitres = entered;
        preview =
            'Reset — ${qty.format(entered)} L → ${qty.format(entered * factor)} kg';
      } else if (belowLast) {
        preview = 'Below last (${qty.format(last)}). Was the meter reset?';
        color = scheme.error;
      } else {
        final d = entered - last!;
        consumptionLitres = d;
        preview = '${qty.format(d)} L → ${qty.format(d * factor)} kg';
      }
    }

    final aboveMax = maxConsumptionLitres != null &&
        consumptionLitres != null &&
        consumptionLitres > maxConsumptionLitres!;

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
            if (aboveMax) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Above expected max (${qty.format(maxConsumptionLitres!)} L) — verify before submitting',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            if (showReset)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                    'Meter was reset (use new reading as consumption)'),
                value: reset,
                onChanged: (v) => onResetChanged(v ?? false),
              ),
          ],
        ),
      ),
    );
  }
}
