import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_meter_point.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;

const _maxToloulLitres = 15000.0;

/// Toloul meter point readings — grid layout mirroring InkMeterReadingsGridScreen.
/// Cumulative entry (delta = consumption) with meter-reset handling, history
/// strip per point, and role-gated date picker (managers/admins only).
class InkMeterPointEntryScreen extends ConsumerStatefulWidget {
  const InkMeterPointEntryScreen({super.key});

  @override
  ConsumerState<InkMeterPointEntryScreen> createState() => _State();
}

class _State extends ConsumerState<InkMeterPointEntryScreen> {
  final _ctrls = <String, TextEditingController>{};
  final _reset = <String, bool>{};
  DateTime _readingDate = DateTime.now();
  bool _submitting = false;

  TextEditingController _ctrl(String id) =>
      _ctrls.putIfAbsent(id, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _readingDate);
    if (dt != null) setState(() => _readingDate = dt);
  }

  Future<void> _submit(
      List<InkMeterPoint> points, Map<String, double> last) async {
    final lines =
        <({String pointId, double reading, double consumption, bool reset})>[];
    final problems = <String>[];
    for (final p in points) {
      final id = p.id!;
      final raw = _ctrl(id).text.trim();
      if (raw.isEmpty) continue;
      final entered = double.tryParse(raw);
      if (entered == null) {
        problems.add('${p.name}: invalid number');
        continue;
      }
      final lastReading = last[id];
      final didReset = _reset[id] ?? false;
      double consumption;
      if (lastReading == null) {
        consumption = 0;
      } else if (didReset) {
        consumption = entered;
      } else {
        consumption = entered - lastReading;
        if (consumption < 0) {
          problems.add('${p.name}: reading below last — tick "meter was reset"');
          continue;
        }
      }
      lines.add((
        pointId: id,
        reading: entered,
        consumption: consumption,
        reset: didReset,
      ));
    }
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(problems.join('\n')),
          backgroundColor: Theme.of(context).colorScheme.error));
      return;
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter at least one reading.')));
      return;
    }

    final qty = NumberFormat('#,##0.##');
    final overMax = lines.where((l) => l.consumption > _maxToloulLitres).map(
        (l) {
      final pt = points.firstWhere((p) => p.id == l.pointId,
          orElse: () => InkMeterPoint(name: l.pointId, linkage: '', sortOrder: 0));
      return '${pt.name}: ${qty.format(l.consumption)} L (max ${qty.format(_maxToloulLitres)} L)';
    }).toList();

    if (overMax.isNotEmpty) {
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
              for (final w in overMax)
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
        await confirmClosedPeriodOverride(context, ref, _readingDate);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).recordMeterPointReadings(
            readingDate: _readingDate,
            lines: lines,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${lines.length} meter reading(s) recorded.')));
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
    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final canEditDate = role_utils.isInkManager(emp) || role_utils.isAdmin(emp);

    final pointsAsync = ref.watch(inkActiveMeterPointsProvider);
    final last = ref.watch(inkLatestMeterPointReadingsProvider).valueOrNull ?? {};
    final recent =
        ref.watch(inkRecentMeterPointReadingsProvider).valueOrNull ?? {};
    final df = DateFormat('EEE d MMM HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Toloul Meter Readings')),
      body: pointsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (points) {
          if (points.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('No meter points yet. A manager must add them '
                      '(Ink hub → Toloul Meter Points).')),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: canEditDate
                    ? OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event),
                        label: Text('Reading date: ${df.format(_readingDate)}'),
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
                            Text('Reading date: ${df.format(_readingDate)}',
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
                    for (final p in points)
                      _PointCard(
                        point: p,
                        controller: _ctrl(p.id!),
                        last: last[p.id],
                        history: recent[p.id] ?? const [],
                        reset: _reset[p.id] ?? false,
                        onResetChanged: (v) =>
                            setState(() => _reset[p.id!] = v),
                        onChanged: () => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed:
                          _submitting ? null : () => _submit(points, last),
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

class _PointCard extends StatelessWidget {
  const _PointCard({
    required this.point,
    required this.controller,
    required this.last,
    required this.history,
    required this.reset,
    required this.onResetChanged,
    required this.onChanged,
  });

  final InkMeterPoint point;
  final TextEditingController controller;
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
    double? consumptionLitres;
    if (entered != null) {
      if (last == null) {
        preview = 'First reading — sets baseline';
        color = scheme.onSurfaceVariant;
      } else if (reset) {
        consumptionLitres = entered;
        preview = 'Reset — ${qty.format(entered)} L';
      } else if (belowLast) {
        preview = 'Below last (${qty.format(last)}). Was the meter reset?';
        color = scheme.error;
      } else {
        consumptionLitres = entered - last!;
        preview = '${qty.format(consumptionLitres)} L';
      }
    }
    final aboveMax =
        consumptionLitres != null && consumptionLitres > _maxToloulLitres;

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
                  child: Text(point.name,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    point.linkageLabelText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
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
                      'Above expected max (${qty.format(_maxToloulLitres)} L) — verify before submitting',
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
                title: const Text('Meter was reset (use new reading as usage)'),
                value: reset,
                onChanged: (v) => onResetChanged(v ?? false),
              ),
          ],
        ),
      ),
    );
  }
}
