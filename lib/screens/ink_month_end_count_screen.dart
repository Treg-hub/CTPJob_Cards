import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../constants/ink_toloul.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/persona_audit.dart';
import '../theme/app_theme.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;

/// Phase 1M — Month-end Count (manager). The factory counts physical stock on a
/// designated date (not necessarily the calendar month-end) and the system
/// auto-creates the adjustment per item from the difference to the ledger
/// (count − ledger), exactly as done manually today. Enter counts for the items
/// you counted; blanks are skipped. Toloul requires factory tank + Lurgi split.
class InkMonthEndCountScreen extends ConsumerStatefulWidget {
  const InkMonthEndCountScreen({super.key});

  @override
  ConsumerState<InkMonthEndCountScreen> createState() => _State();
}

class _State extends ConsumerState<InkMonthEndCountScreen> {
  final _ctrls = <String, TextEditingController>{};
  DateTime _countDate = DateTime.now();
  bool _submitting = false;

  TextEditingController _ctrl(String code) =>
      _ctrls.putIfAbsent(code, () => TextEditingController());

  TextEditingController _toloulFactoryCtrl() => _ctrl('${kToloulItemCode}_factory');
  TextEditingController _toloulLurgiCtrl() => _ctrl('${kToloulItemCode}_lurgi');

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _countDate);
    if (dt != null) setState(() => _countDate = dt);
  }

  Future<void> _submit(List<InkStockItem> items) async {
    if (!guardPersonaSubmit(context)) return;
    final lines = <
        ({
          String itemCode,
          double counted,
          double ledgerBalance,
          double wac,
          double? factoryCounted,
          double? lurgiCounted,
        })>[];

    for (final item in items) {
      if (item.isToloul) {
        final factoryRaw = _toloulFactoryCtrl().text.trim();
        final lurgiRaw = _toloulLurgiCtrl().text.trim();
        if (factoryRaw.isEmpty && lurgiRaw.isEmpty) continue;
        if (factoryRaw.isEmpty || lurgiRaw.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Toloul: enter both factory tank and Lurgi counts, or leave both blank.')));
          return;
        }
        final factory = double.tryParse(factoryRaw);
        final lurgi = double.tryParse(lurgiRaw);
        if (factory == null ||
            lurgi == null ||
            factory < 0 ||
            lurgi < 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Toloul: enter valid non-negative quantities.')));
          return;
        }
        lines.add((
          itemCode: item.itemCode,
          counted: factory + lurgi,
          ledgerBalance: item.currentBalance,
          wac: item.weightedAverageCost,
          factoryCounted: factory,
          lurgiCounted: lurgi,
        ));
        continue;
      }

      final raw = _ctrl(item.itemCode).text.trim();
      if (raw.isEmpty) continue;
      final counted = double.tryParse(raw);
      if (counted == null || counted < 0) continue;
      lines.add((
        itemCode: item.itemCode,
        counted: counted,
        ledgerBalance: item.currentBalance,
        wac: item.weightedAverageCost,
        factoryCounted: null,
        lurgiCounted: null,
      ));
    }

    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter at least one counted quantity.')));
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _countDate);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).recordMonthEndCount(
            countDate: _countDate,
            lines: lines,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      final adjusted = lines
          .where((l) => (l.counted - l.ledgerBalance).abs() >= 1e-9)
          .length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Count recorded — $adjusted adjustment(s) made.')));
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
    final isManager = role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Month-end Count')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final itemsAsync = ref.watch(inkStockItemsProvider);
    final df = DateFormat('EEE d MMM yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Month-end Count')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text('Count date: ${df.format(_countDate)}'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    alignment: Alignment.centerLeft),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final item in items)
                    if (item.isToloul)
                      _ToloulCountCard(
                        item: item,
                        factoryController: _toloulFactoryCtrl(),
                        lurgiController: _toloulLurgiCtrl(),
                        onChanged: () => setState(() {}),
                      )
                    else
                      _CountCard(
                        item: item,
                        controller: _ctrl(item.itemCode),
                        onChanged: () => setState(() {}),
                      ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _submitting ? null : () => _submit(items),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: const Text('Record count & adjust'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.item,
    required this.controller,
    required this.onChanged,
  });
  final InkStockItem item;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final qty = NumberFormat('#,##0.##');
    final counted = double.tryParse(controller.text.trim());
    final delta = counted == null ? null : counted - item.currentBalance;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text('Ledger: ${qty.format(item.currentBalance)} ${item.unit}',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (delta != null && delta.abs() >= 1e-9)
                    Text(
                      'Adjust ${delta > 0 ? '+' : ''}${qty.format(delta)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: delta > 0
                              ? Theme.of(context).appColors.statusCompleted
                              : scheme.error),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: 'Counted',
                  suffixText: item.unit,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToloulCountCard extends StatelessWidget {
  const _ToloulCountCard({
    required this.item,
    required this.factoryController,
    required this.lurgiController,
    required this.onChanged,
  });

  final InkStockItem item;
  final TextEditingController factoryController;
  final TextEditingController lurgiController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final qty = NumberFormat('#,##0.##');
    final factory = double.tryParse(factoryController.text.trim());
    final lurgi = double.tryParse(lurgiController.text.trim());
    final consolidated =
        factory != null && lurgi != null ? factory + lurgi : null;
    final delta = consolidated == null
        ? null
        : consolidated - item.currentBalance;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.displayName,
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              'Ledger (consolidated): ${qty.format(item.currentBalance)} ${item.unit}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (item.factoryTankBalance != null)
              Text(
                'Factory tank (operational): ${qty.format(item.operationalBalance)} ${item.unit}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (consolidated != null)
              Text(
                'Total counted: ${qty.format(consolidated)} ${item.unit}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (delta != null && delta.abs() >= 1e-9)
              Text(
                'Adjust ${delta > 0 ? '+' : ''}${qty.format(delta)}',
                style: TextStyle(
                  fontSize: 12,
                  color: delta > 0
                      ? Theme.of(context).appColors.statusCompleted
                      : scheme.error,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: factoryController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: 'Factory tank',
                      suffixText: item.unit,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lurgiController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: 'Lurgi',
                      suffixText: item.unit,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}