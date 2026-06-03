import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fleet_cost_line.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';

/// Cost overview and reports for fleet cost managers and admins.
/// Shows month/YTD KPIs, per-asset spend list, and CSV export.
class FleetReportsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const FleetReportsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<FleetReportsScreen> createState() =>
      _FleetReportsScreenState();
}

class _FleetReportsScreenState extends ConsumerState<FleetReportsScreen> {
  final _service = FleetService();

  /// null = current month; true = YTD
  bool _isYtd = false;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _exporting = false;

  DateTime get _from {
    if (_isYtd) return DateTime(DateTime.now().year, 1, 1);
    return _selectedMonth;
  }

  DateTime get _to {
    if (_isYtd) return DateTime.now();
    return DateTime(
        _selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
  }

  Future<void> _previousMonth() async {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  Future<void> _nextMonth() async {
    final now = DateTime.now();
    final next =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _selectedMonth = next);
  }

  Future<void> _export(List<FleetCostLine> lines) async {
    setState(() => _exporting = true);
    try {
      final rows = <List<dynamic>>[
        [
          'Date',
          'Asset Name',
          'Asset Tag',
          'Work Record #',
          'Work Type',
          'Labour Hours',
          'Mechanic Name',
          'Cost Category',
          'Description',
          'Amount ZAR',
          'Invoice Ref',
          'Supplier',
          'Entered By',
        ],
        ...lines.map((l) => [
              DateFormat('yyyy-MM-dd').format(l.costDate),
              l.assetName,
              '', // asset tag — not stored in cost line; blank is acceptable
              l.workNumber ?? '',
              '', // work type — not stored in cost line
              '', // labour hours — not stored
              '', // mechanic name — not stored
              l.category.displayLabel,
              l.description,
              l.amountZar.toStringAsFixed(2),
              l.invoiceRef ?? '',
              l.supplier ?? '',
              l.enteredByName,
            ]),
      ];

      final csv = CsvEncoder().convert(rows);
      final dir = await getTemporaryDirectory();
      final period = _isYtd
          ? 'YTD${DateTime.now().year}'
          : DateFormat('yyyy-MM').format(_selectedMonth);
      final file = File('${dir.path}/fleet_costs_$period.csv');
      await file.writeAsString(csv);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Fleet Costs $period',
          text: 'Fleet cost lines export for $period',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat('MMMM yyyy');
    final dateFmt = DateFormat('d MMM yyyy');

    final body = StreamBuilder<List<FleetCostLine>>(
        stream: _service.watchCostLines(from: _from, to: _to, limit: 500),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final lines = snapshot.data ?? [];

          // Compute KPIs
          double totalZar = 0;
          for (final l in lines) {
            totalZar += l.amountZar;
          }

          // Per-asset spend
          final Map<String, double> byAsset = {};
          for (final l in lines) {
            byAsset[l.assetName] = (byAsset[l.assetName] ?? 0) + l.amountZar;
          }
          final sortedAssets = byAsset.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return Column(
            children: [
              // ── Period selector ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(_isYtd
                          ? 'Year to Date'
                          : monthFmt.format(_selectedMonth)),
                      selected: !_isYtd,
                      selectedColor: kBrandOrange,
                      labelStyle: TextStyle(
                          color: !_isYtd ? Colors.white : null),
                      onSelected: (_) =>
                          setState(() => _isYtd = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('YTD'),
                      selected: _isYtd,
                      selectedColor: kBrandOrange,
                      labelStyle: TextStyle(
                          color: _isYtd ? Colors.white : null),
                      onSelected: (_) =>
                          setState(() => _isYtd = true),
                    ),
                    const Spacer(),
                    if (!_isYtd) ...[
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _previousMonth,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── KPI cards ──────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _KpiCard(
                            label: _isYtd
                                ? 'Total YTD'
                                : 'Total This Month',
                            value: 'R ${NumberFormat('#,##0.00').format(totalZar)}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _KpiCard(
                            label: 'Cost Lines',
                            value: lines.length.toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Per-asset spend bar ────────────────────────────────
                    if (sortedAssets.isNotEmpty) ...[
                      const Text('Spend per Asset',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 8),
                      ...sortedAssets.map((e) {
                        final pct = totalZar > 0
                            ? e.value / totalZar
                            : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(e.key,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                      'R ${NumberFormat('#,##0.00').format(e.value)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct.toDouble(),
                                  backgroundColor: Colors.grey[200],
                                  valueColor:
                                      const AlwaysStoppedAnimation(
                                          kBrandOrange),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(),
                    ],

                    // ── Cost lines table ──────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cost Lines',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        if (lines.isNotEmpty)
                          TextButton.icon(
                            icon: _exporting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.download,
                                    size: 18, color: kBrandOrange),
                            label: const Text('Export CSV',
                                style:
                                    TextStyle(color: kBrandOrange)),
                            onPressed: _exporting
                                ? null
                                : () => _export(lines),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (lines.isEmpty)
                      const Text('No cost lines for this period.',
                          style: TextStyle(color: Colors.grey))
                    else
                      ...lines.map((l) => _CostLineTile(
                            line: l, dateFmt: dateFmt)),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          );
        },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cost Reports'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _CostLineTile extends StatelessWidget {
  const _CostLineTile({required this.line, required this.dateFmt});
  final FleetCostLine line;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(
            child: Text(line.description,
                style: const TextStyle(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(
            'R ${line.amountZar.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Text(
        '${line.assetName}  •  ${line.category.displayLabel}'
        '${line.invoiceRef != null ? '  •  ${line.invoiceRef}' : ''}'
        '  •  ${dateFmt.format(line.costDate)}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
