import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../providers/ink_provider.dart';
import '../services/ink_ledger.dart';

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
class InkMonthEndReportScreen extends ConsumerStatefulWidget {
  const InkMonthEndReportScreen({super.key});

  @override
  ConsumerState<InkMonthEndReportScreen> createState() => _State();
}

class _State extends ConsumerState<InkMonthEndReportScreen> {
  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat('#,##0.00');
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _step(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  List<_Row> _build(List<InkStockItem> items, List<InkTransaction> txns) {
    final start = DateTime(_month.year, _month.month);
    final nextStart = DateTime(_month.year, _month.month + 1);
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
    rows.sort((a, b) {
      final c = a.item.itemClass.index.compareTo(b.item.itemClass.index);
      return c != 0 ? c : a.item.displayName.compareTo(b.item.displayName);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final txnsAsync = ref.watch(inkAllTransactionsProvider);
    final mf = DateFormat('MMMM yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Month-end Report')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                    onPressed: () => _step(-1),
                    icon: const Icon(Icons.chevron_left)),
                Text(mf.format(_month),
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    onPressed: () => _step(1),
                    icon: const Icon(Icons.chevron_right)),
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
        ],
      ),
    );
  }
}
