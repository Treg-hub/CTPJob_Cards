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
import 'ink_stock_item_detail_screen.dart' show inkTxnLabel;

/// One summary row per item — mirrors the legacy month-end sheet:
/// Opening (WAC/Bal/Value), Manufacture+Purchase (qty/value), Consumption,
/// Recoveries, Adjustments, Revaluations, Closing (Bal/Value/WAC).
/// All movement values are derived from the replay (value delta per step).
class _Row {
  _Row(this.item);
  final InkStockItem item;
  double openBal = 0, openWac = 0;
  double inQty = 0, inVal = 0; // purchase + manufacture + opening
  double consQty = 0, consVal = 0; // consumption* (signed, negative)
  double recQty = 0, recVal = 0; // recovery
  double adjQty = 0, adjVal = 0; // adjustment (signed)
  double revalVal = 0; // revaluation value change (qty 0)
  double closeBal = 0, closeWac = 0;
  double get openVal => openBal * openWac;
  double get closeVal => closeBal * closeWac;
}

/// One line in the full transaction-list export.
class _TxnLine {
  _TxnLine(this.date, this.seq, this.item, this.type, this.qty, this.value,
      this.balance, this.wac);
  final DateTime date;
  final String seq;
  final String item;
  final String type;
  final double qty;
  final double value;
  final double balance;
  final double wac;
}

/// Month-end roll-forward report (manager). Reproduces the stock summary sheet
/// from the ledger, exports a summary PDF/CSV and a full transaction-list PDF.
/// Managers can Finalise/Re-open the displayed month (period-close lock).
class InkMonthEndReportScreen extends ConsumerStatefulWidget {
  const InkMonthEndReportScreen({super.key});

  @override
  ConsumerState<InkMonthEndReportScreen> createState() => _State();
}

class _State extends ConsumerState<InkMonthEndReportScreen> {
  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat('#,##0.00');
  static final _wac = NumberFormat('#,##0.0000');
  static final _fileDateFmt = DateFormat('yyyy-MM-dd');

  // Period is [_from 00:00, _to end-of-day]. Free dates — set to your count dates.
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
  }

  DateTime get _periodEnd => _to.add(const Duration(days: 1));

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

  bool _inPeriod(DateTime t) =>
      !t.isBefore(_from) && t.isBefore(_periodEnd);

  // ── Summary roll-forward (per item) ───────────────────────────────────────
  List<_Row> _build(List<InkStockItem> items, List<InkTransaction> txns) {
    final byItem = <String, List<InkTransaction>>{};
    for (final t in txns) {
      (byItem[t.stockItemCode] ??= []).add(t);
    }
    final rows = <_Row>[];
    for (final item in items) {
      final its = byItem[item.itemCode] ?? const [];
      final before = its
          .where((t) => t.effectiveAt.isBefore(_from))
          .map((t) => t.toLedgerEntry())
          .toList();
      final upToEnd = its
          .where((t) => t.effectiveAt.isBefore(_periodEnd))
          .map((t) => t.toLedgerEntry())
          .toList();
      final opening = replayLedger(entries: before);
      final result = replayLedger(entries: upToEnd);
      final row = _Row(item)
        ..openBal = opening.balance
        ..openWac = opening.wac
        ..closeBal = result.balance
        ..closeWac = result.wac;
      for (final step in result.steps) {
        final e = step.entry;
        if (!_inPeriod(e.effectiveAt)) continue;
        final vd = step.balanceAfter * step.wacAfter -
            step.balanceBefore * step.wacBefore;
        switch (e.type) {
          case InkTxnType.purchase:
          case InkTxnType.manufacture:
          case InkTxnType.opening:
            row.inQty += e.quantityDelta;
            row.inVal += vd;
            break;
          case InkTxnType.recovery:
            row.recQty += e.quantityDelta;
            row.recVal += vd;
            break;
          case InkTxnType.adjustment:
            row.adjQty += e.quantityDelta;
            row.adjVal += vd;
            break;
          case InkTxnType.consumptionMeter:
          case InkTxnType.consumptionProduction:
          case InkTxnType.consumptionTolulWash:
          case InkTxnType.consumptionTolulProduction:
            row.consQty += e.quantityDelta; // negative
            row.consVal += vd; // negative
            break;
          case InkTxnType.revaluation:
            row.revalVal += vd;
            break;
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

  // ── Full transaction list for the period ──────────────────────────────────
  List<_TxnLine> _buildTxnList(
      List<InkStockItem> items, List<InkTransaction> txns) {
    final names = {for (final i in items) i.itemCode: i.displayName};
    final lines = <_TxnLine>[];
    for (final t in txns) {
      if (t.voided || !_inPeriod(t.effectiveAt)) continue;
      final isIn = t.type == InkTxnType.purchase ||
          t.type == InkTxnType.manufacture ||
          t.type == InkTxnType.opening;
      final value = (isIn && t.totalCost != null)
          ? t.totalCost!
          : t.quantityDelta * t.wacAtTime;
      lines.add(_TxnLine(
        t.effectiveAt,
        t.seqNumber ?? 'pending',
        names[t.stockItemCode] ?? t.stockItemCode,
        inkTxnLabel(t.type),
        t.quantityDelta,
        value,
        t.balanceAfter,
        t.wacAtTime,
      ));
    }
    lines.sort((a, b) => a.date.compareTo(b.date));
    return lines;
  }

  // ── Period close / re-open ────────────────────────────────────────────────
  Future<void> _finalisePeriod(String pk) async {
    final ok = await _confirm('Finalise period?',
        'Close period $pk?\n\nFurther transactions into this month will require '
        'a manager override and will flag the report for re-issue.', 'Finalise');
    if (ok != true || !mounted) return;
    await ref.read(inkServiceProvider).closePeriod(pk);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Period $pk finalised.')));
    }
  }

  Future<void> _reopenPeriod(String pk) async {
    final ok = await _confirm('Re-open period?',
        'Re-open period $pk?\n\nThis removes the close lock and the re-issue flag.',
        'Re-open');
    if (ok != true || !mounted) return;
    await ref.read(inkServiceProvider).reopenPeriod(pk);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Period $pk re-opened.')));
    }
  }

  Future<bool?> _confirm(String title, String body, String action) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      );

  // ── Exports ───────────────────────────────────────────────────────────────
  static const _summaryHeaders = [
    'Item', 'Unit', 'Open WAC', 'Open Bal', 'Open Value', //
    'Mfg/Pur', 'Mfg/Pur Value', 'Cons', 'Cons Value', //
    'Rec', 'Rec Value', 'Adj', 'Adj Value', 'Reval Value', //
    'Close Bal', 'Close Value', 'Close WAC',
  ];

  List<String> _summaryRowStrings(_Row r) => [
        r.item.displayName,
        r.item.unit,
        _wac.format(r.openWac),
        _qty.format(r.openBal),
        _money.format(r.openVal),
        r.inQty == 0 ? '–' : _qty.format(r.inQty),
        r.inVal == 0 ? '–' : _money.format(r.inVal),
        r.consQty == 0 ? '–' : _qty.format(r.consQty),
        r.consVal == 0 ? '–' : _money.format(r.consVal),
        r.recQty == 0 ? '–' : _qty.format(r.recQty),
        r.recVal == 0 ? '–' : _money.format(r.recVal),
        r.adjQty == 0 ? '–' : _qty.format(r.adjQty),
        r.adjVal == 0 ? '–' : _money.format(r.adjVal),
        r.revalVal == 0 ? '–' : _money.format(r.revalVal),
        _qty.format(r.closeBal),
        _money.format(r.closeVal),
        _wac.format(r.closeWac),
      ];

  Future<void> _share(File file, String text) =>
      SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: text));

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: err ? Colors.red : Colors.green));
  }

  Future<void> _exportCsv(
      List<_Row> rows, double tolRecovery, double tolUsage) async {
    if (rows.isEmpty) return _toast('No data to export', err: true);
    try {
      final data = <List<dynamic>>[
        _summaryHeaders,
        for (final r in rows)
          [
            r.item.displayName, r.item.unit, r.openWac, r.openBal, r.openVal,
            r.inQty, r.inVal, r.consQty, r.consVal, r.recQty, r.recVal, //
            r.adjQty, r.adjVal, r.revalVal, r.closeBal, r.closeVal, r.closeWac,
          ],
        [],
        ['Toloul Recovery (L)', tolRecovery],
        ['Toloul Usage (L)', tolUsage],
      ];
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/ink_summary_${_fileDateFmt.format(_from)}_${_fileDateFmt.format(_to)}.csv');
      await f.writeAsString(const CsvEncoder().convert(data));
      await _share(f, 'Ink Month-end Summary (CSV)');
      _toast('CSV exported & shared');
    } catch (e) {
      _toast('CSV export failed: $e', err: true);
    }
  }

  Future<void> _exportSummaryPdf(
      List<_Row> rows, double tolRecovery, double tolUsage) async {
    if (rows.isEmpty) return _toast('No data to export', err: true);
    try {
      final fromStr = DateFormat('d MMM yyyy').format(_from);
      final toStr = DateFormat('d MMM yyyy').format(_to);
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text('Ink Month-end Summary   $fromStr – $toStr',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: _summaryHeaders,
            data: [for (final r in rows) _summaryRowStrings(r)],
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.center},
          ),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            pw.Text('Toloul Recovery: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('${_qty.format(tolRecovery)} L'),
            pw.SizedBox(width: 24),
            pw.Text('Toloul Usage: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('${_qty.format(tolUsage)} L'),
          ]),
        ],
      ));
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/ink_summary_${_fileDateFmt.format(_from)}_${_fileDateFmt.format(_to)}.pdf');
      await f.writeAsBytes(await doc.save());
      await _share(f, 'Ink Month-end Summary (PDF)');
    } catch (e) {
      _toast('PDF export failed: $e', err: true);
    }
  }

  Future<void> _exportTxnListPdf(List<_TxnLine> lines) async {
    if (lines.isEmpty) return _toast('No transactions in period', err: true);
    try {
      final fromStr = DateFormat('d MMM yyyy').format(_from);
      final toStr = DateFormat('d MMM yyyy').format(_to);
      final df = DateFormat('d MMM HH:mm');
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text('Ink Transactions   $fromStr – $toStr',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date', 'No.', 'Item', 'Type', 'Qty', 'Value', 'Balance', 'WAC'
            ],
            data: [
              for (final l in lines)
                [
                  df.format(l.date),
                  l.seq,
                  l.item,
                  l.type,
                  _qty.format(l.qty),
                  _money.format(l.value),
                  _qty.format(l.balance),
                  _wac.format(l.wac),
                ]
            ],
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 8),
          pw.Text('${lines.length} transactions',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ],
      ));
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/ink_transactions_${_fileDateFmt.format(_from)}_${_fileDateFmt.format(_to)}.pdf');
      await f.writeAsBytes(await doc.save());
      await _share(f, 'Ink Transactions (PDF)');
    } catch (e) {
      _toast('PDF export failed: $e', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final txnsAsync = ref.watch(inkAllTransactionsProvider);
    final settings = ref.watch(inkSettingsProvider).valueOrNull;
    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final isManager = role_utils.isInkManager(emp);
    final rf = DateFormat('d MMM yyyy');
    final pk = InkSettings.periodKey(_to);
    final isClosed = settings?.closedPeriods.contains(pk) ?? false;
    final needsReissue = settings?.periodsNeedingReissue.contains(pk) ?? false;
    final scheme = Theme.of(context).colorScheme;

    // Toloul meter-point totals for the period (no stock effect).
    final pointLinkage = {
      for (final p in (ref.watch(inkAllMeterPointsProvider).valueOrNull ?? []))
        p.id: p.linkage
    };
    final mpReadings =
        ref.watch(inkMeterPointReadingsProvider).valueOrNull ?? [];
    var tolRecovery = 0.0, tolUsage = 0.0;
    for (final r in mpReadings) {
      if (!_inPeriod(r.readingDate)) continue;
      final lk = pointLinkage[r.pointId];
      if (lk == 'recovery') tolRecovery += r.consumption;
      if (lk == 'usage') tolUsage += r.consumption;
    }

    final isLoading = itemsAsync.isLoading || txnsAsync.isLoading;
    final items = itemsAsync.valueOrNull ?? [];
    final txns = txnsAsync.valueOrNull ?? [];
    final rows = isLoading ? <_Row>[] : _build(items, txns);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Month-end Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Summary CSV',
            onPressed:
                isLoading ? null : () => _exportCsv(rows, tolRecovery, tolUsage),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Summary PDF',
            onPressed: isLoading
                ? null
                : () => _exportSummaryPdf(rows, tolRecovery, tolUsage),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Transaction list PDF',
            onPressed: isLoading
                ? null
                : () => _exportTxnListPdf(_buildTxnList(items, txns)),
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
          if (needsReissue)
            _banner(scheme.errorContainer, scheme.onErrorContainer,
                Icons.warning_amber_rounded,
                'Period $pk is closed but has had transactions since — needs re-issue.')
          else if (isClosed)
            _banner(scheme.secondaryContainer, scheme.onSecondaryContainer,
                Icons.lock, 'Period $pk is finalised.'),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
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
            ]),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 38,
                        columnSpacing: 14,
                        columns: [
                          for (final h in _summaryHeaders)
                            DataColumn(
                                label: Text(h,
                                    style: const TextStyle(fontSize: 11)),
                                numeric: h != 'Item' && h != 'Unit'),
                        ],
                        rows: [
                          for (final r in rows)
                            DataRow(
                                cells: [
                              for (final c in _summaryRowStrings(r))
                                DataCell(
                                    Text(c, style: const TextStyle(fontSize: 11)))
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
                _stat(context, 'Toloul Recovery', '${_qty.format(tolRecovery)} L'),
                _stat(context, 'Toloul Usage', '${_qty.format(tolUsage)} L'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(Color bg, Color fg, IconData icon, String text) => Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ]),
      );

  Widget _stat(BuildContext context, String label, String value) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
}
