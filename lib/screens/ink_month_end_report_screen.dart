import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_settings.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../services/ink_ledger.dart';
import '../utils/role.dart' as role_utils;

class _Row {
  _Row(this.item);
  final InkStockItem item;
  double openBal = 0, inQty = 0, consQty = 0, recQty = 0, adjQty = 0;
  double closeBal = 0, closeWac = 0;
  double get closeValue => closeBal * closeWac;
}

/// Month-end roll-forward report (manager) — reproduces the stock summary
/// sheet from the ledger: Opening, In (purchase+manufacture), Consumption,
/// Recovery, Adjustment, Closing balance + WAC + value, per item, for a month.
///
/// Managers can Finalise the displayed month (closes its period) or Re-open it.
/// Banners show if the period is closed or needs re-issue.
class InkMonthEndReportScreen extends ConsumerStatefulWidget {
  const InkMonthEndReportScreen({super.key});

  @override
  ConsumerState<InkMonthEndReportScreen> createState() => _State();
}

class _State extends ConsumerState<InkMonthEndReportScreen> {
  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat('#,##0.00');
  // Period is [_from 00:00, _to end-of-day]. Defaults to month-to-date but the
  // dates are free — set them to your designated count dates (count-to-count).
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        final picked = DateTime(d.year, d.month, d.day);
        if (isFrom) {
          _from = picked;
        } else {
          _to = picked;
        }
      });
    }
  }

  List<_Row> _build(List<InkStockItem> items, List<InkTransaction> txns) {
    final start = _from;
    final nextStart = _to.add(const Duration(days: 1)); // include the whole _to day
    final byItem = <String, List<InkTransaction>>{};
    for (final t in txns) {
      (byItem[t.stockItemCode] ??= []).add(t);
    }
    final rows = <_Row>[];
    for (final item in items) {
      final its = byItem[item.itemCode] ?? const [];
      final before = its
          .where((t) => t.effectiveAt.isBefore(start))
          .map((t) => t.toLedgerEntry())
          .toList();
      final upToEnd = its
          .where((t) => t.effectiveAt.isBefore(nextStart))
          .map((t) => t.toLedgerEntry())
          .toList();
      final opening = replayLedger(entries: before);
      final closing = replayLedger(entries: upToEnd);
      final row = _Row(item)
        ..openBal = opening.balance
        ..closeBal = closing.balance
        ..closeWac = closing.wac;
      for (final t in its) {
        if (t.effectiveAt.isBefore(start) || !t.effectiveAt.isBefore(nextStart)) {
          continue;
        }
        switch (t.type) {
          case InkTxnType.purchase:
          case InkTxnType.manufacture:
          case InkTxnType.opening:
            row.inQty += t.quantityDelta;
            break;
          case InkTxnType.recovery:
            row.recQty += t.quantityDelta;
            break;
          case InkTxnType.adjustment:
            row.adjQty += t.quantityDelta;
            break;
          case InkTxnType.consumptionMeter:
          case InkTxnType.consumptionProduction:
          case InkTxnType.consumptionTolulWash:
          case InkTxnType.consumptionTolulProduction:
            row.consQty += -t.quantityDelta;
            break;
          case InkTxnType.revaluation:
          case InkTxnType.transfer:
          case InkTxnType.correction:
            break;
        }
      }
      rows.add(row);
    }
    rows.sort((a, b) => a.item.displayOrder.compareTo(b.item.displayOrder));
    return rows;
  }

  Future<void> _finalisePeriod(String pk) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalise period?'),
        content: Text(
          'Close period $pk?\n\n'
          'Further transactions into this month will require a manager '
          'override and will flag the report for re-issue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalise'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(inkServiceProvider).closePeriod(pk);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Period $pk finalised.')));
  }

  Future<void> _reopenPeriod(String pk) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-open period?'),
        content: Text(
          'Re-open period $pk?\n\n'
          'This removes the close lock and the re-issue flag.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-open'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(inkServiceProvider).reopenPeriod(pk);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Period $pk re-opened.')));
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final txnsAsync = ref.watch(inkAllTransactionsProvider);
    final settingsAsync = ref.watch(inkSettingsProvider);
    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final isManager = role_utils.isInkManager(emp);
    final rf = DateFormat('d MMM yyyy');
    final settings = settingsAsync.valueOrNull;
    final pk = InkSettings.periodKey(_to);
    final isClosed = settings?.closedPeriods.contains(pk) ?? false;
    final needsReissue = settings?.periodsNeedingReissue.contains(pk) ?? false;

    // Toloul meter-point totals for the period (no stock effect).
    final pointLinkage = {
      for (final p in (ref.watch(inkAllMeterPointsProvider).valueOrNull ?? []))
        p.id: p.linkage
    };
    final mpReadings =
        ref.watch(inkMeterPointReadingsProvider).valueOrNull ?? [];
    final periodEnd = _to.add(const Duration(days: 1));
    var tolRecovery = 0.0, tolUsage = 0.0;
    for (final r in mpReadings) {
      if (r.readingDate.isBefore(_from) || !r.readingDate.isBefore(periodEnd)) {
        continue;
      }
      final lk = pointLinkage[r.pointId];
      if (lk == 'recovery') {
        tolRecovery += r.consumption;
      } else if (lk == 'usage') {
        tolUsage += r.consumption;
      }
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Month-end Report'),
        actions: isManager
            ? [
                if (isClosed)
                  TextButton.icon(
                    onPressed: () => _reopenPeriod(pk),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Re-open'),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _finalisePeriod(pk),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Finalise'),
                  ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // Status banners — shown when _to period is closed / needs re-issue.
          if (needsReissue)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: scheme.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Period $pk is closed but has had transactions posted '
                      'since finalisation — report needs re-issue.',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            )
          else if (isClosed)
            Container(
              width: double.infinity,
              color: scheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.lock, color: scheme.onSecondaryContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Period $pk is finalised.',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.event),
                    label: Text('From ${rf.format(_from)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.event),
                    label: Text('To ${rf.format(_to)}'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: (itemsAsync.isLoading || txnsAsync.isLoading)
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final rows = _build(
                        itemsAsync.valueOrNull ?? [], txnsAsync.valueOrNull ?? []);
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowHeight: 38,
                          dataRowMinHeight: 34,
                          dataRowMaxHeight: 40,
                          columnSpacing: 18,
                          columns: const [
                            DataColumn(label: Text('Item')),
                            DataColumn(label: Text('Open'), numeric: true),
                            DataColumn(label: Text('In'), numeric: true),
                            DataColumn(label: Text('Cons'), numeric: true),
                            DataColumn(label: Text('Rec'), numeric: true),
                            DataColumn(label: Text('Adj'), numeric: true),
                            DataColumn(label: Text('Close'), numeric: true),
                            DataColumn(label: Text('WAC'), numeric: true),
                            DataColumn(label: Text('Value'), numeric: true),
                          ],
                          rows: [
                            for (final r in rows)
                              DataRow(cells: [
                                DataCell(Text(r.item.displayName)),
                                DataCell(Text(_qty.format(r.openBal))),
                                DataCell(Text(r.inQty == 0 ? '–' : _qty.format(r.inQty))),
                                DataCell(Text(r.consQty == 0 ? '–' : _qty.format(r.consQty))),
                                DataCell(Text(r.recQty == 0 ? '–' : _qty.format(r.recQty))),
                                DataCell(Text(r.adjQty == 0 ? '–' : _qty.format(r.adjQty))),
                                DataCell(Text(_qty.format(r.closeBal))),
                                DataCell(Text(_money.format(r.closeWac))),
                                DataCell(Text(_money.format(r.closeValue))),
                              ]),
                          ],
                        ),
                      ),
                    );
                  }),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: scheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(children: [
                  Text('Toloul Recovery',
                      style: Theme.of(context).textTheme.labelMedium),
                  Text('${_qty.format(tolRecovery)} L',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                Column(children: [
                  Text('Toloul Usage',
                      style: Theme.of(context).textTheme.labelMedium),
                  Text('${_qty.format(tolUsage)} L',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
