import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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

  // ── Export helpers ────────────────────────────────────────────────────────

  static final _wac = NumberFormat('#,##0.0000');
  static final _fileDateFmt = DateFormat('yyyy-MM-dd');

  /// Build a flat CSV-ready list from computed rows + toloul totals.
  List<List<dynamic>> _buildCsvData(
      List<_Row> rows, double tolRecovery, double tolUsage) {
    final header = [
      'Item',
      'Unit',
      'Open',
      'In',
      'Cons',
      'Rec',
      'Adj',
      'Close',
      'WAC',
      'Value',
    ];
    final dataRows = rows.map((r) => [
          r.item.displayName,
          r.item.unit,
          r.openBal,
          r.inQty,
          r.consQty,
          r.recQty,
          r.adjQty,
          r.closeBal,
          r.closeWac,
          r.closeValue,
        ]);
    return [
      header,
      ...dataRows,
      [], // blank separator
      ['Toloul Recovery (L)', tolRecovery],
      ['Toloul Usage (L)', tolUsage],
    ];
  }

  Future<void> _exportCsv(
      List<_Row> rows, double tolRecovery, double tolUsage) async {
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export')));
      }
      return;
    }
    try {
      final csvData = _buildCsvData(rows, tolRecovery, tolUsage);
      final csvString = const CsvEncoder().convert(csvData);
      final dir = await getTemporaryDirectory();
      final fromStr = _fileDateFmt.format(_from);
      final toStr = _fileDateFmt.format(_to);
      final file =
          File('${dir.path}/ink_month_end_${fromStr}_$toStr.csv');
      await file.writeAsString(csvString);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Ink Month-end Report $fromStr – $toStr (CSV)',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('CSV exported & shared'),
                backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('CSV export failed: $e'),
                backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportPdf(
      List<_Row> rows, double tolRecovery, double tolUsage) async {
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export')));
      }
      return;
    }
    try {
      final fromStr = DateFormat('d MMM yyyy').format(_from);
      final toStr = DateFormat('d MMM yyyy').format(_to);
      final title = 'Ink Month-end Report  $fromStr – $toStr';

      final tableHeaders = [
        'Item',
        'Unit',
        'Open',
        'In',
        'Cons',
        'Rec',
        'Adj',
        'Close',
        'WAC',
        'Value',
      ];
      final tableData = rows
          .map((r) => [
                r.item.displayName,
                r.item.unit,
                _qty.format(r.openBal),
                r.inQty == 0 ? '–' : _qty.format(r.inQty),
                r.consQty == 0 ? '–' : _qty.format(r.consQty),
                r.recQty == 0 ? '–' : _qty.format(r.recQty),
                r.adjQty == 0 ? '–' : _qty.format(r.adjQty),
                _qty.format(r.closeBal),
                _wac.format(r.closeWac),
                _money.format(r.closeValue),
              ])
          .toList();

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => [
            pw.Text(
              title,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableData,
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.centerRight,
                9: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 16),
            pw.Row(children: [
              pw.Text('Toloul Recovery: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('${_qty.format(tolRecovery)} L'),
              pw.SizedBox(width: 24),
              pw.Text('Toloul Usage: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('${_qty.format(tolUsage)} L'),
            ]),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated ${DateFormat('d MMM yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final fromFile = _fileDateFmt.format(_from);
      final toFile = _fileDateFmt.format(_to);
      final file =
          File('${dir.path}/ink_month_end_${fromFile}_$toFile.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Ink Month-end Report $fromFile – $toFile (PDF)',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('PDF export failed: $e'),
                backgroundColor: Colors.red));
      }
    }
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

    // Pre-compute rows when data is ready so export actions can reuse them.
    final isLoading = itemsAsync.isLoading || txnsAsync.isLoading;
    final rows = isLoading
        ? <_Row>[]
        : _build(
            itemsAsync.valueOrNull ?? [], txnsAsync.valueOrNull ?? []);

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Month-end Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Export CSV',
            onPressed: isLoading
                ? null
                : () => _exportCsv(rows, tolRecovery, tolUsage),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: isLoading
                ? null
                : () => _exportPdf(rows, tolRecovery, tolUsage),
          ),
          if (isManager)
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
        ],
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
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
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
                  ),
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
