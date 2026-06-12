import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_cost_line.dart';
import '../models/fleet_settings.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_cost_widgets.dart';

/// Cost overview and reports for fleet cost managers and admins.
class FleetReportsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const FleetReportsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<FleetReportsScreen> createState() =>
      _FleetReportsScreenState();
}

class _FleetReportsScreenState extends ConsumerState<FleetReportsScreen> {
  final _service = FleetService();

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
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
      23,
      59,
      59,
    );
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
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
          'Work Record #',
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
              l.workNumber ?? '',
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
          text: 'Fleet cost export for $period',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Map<FleetCostCategory, double> _byCategory(List<FleetCostLine> lines) {
    final map = <FleetCostCategory, double>{};
    for (final l in lines) {
      map[l.category] = (map[l.category] ?? 0) + l.amountZar;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat('MMMM yyyy');
    final dateFmt = DateFormat('d MMM yyyy');
    final moneyFmt = NumberFormat('#,##0.00');

    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;
    final costMgrUx = role_utils.isFleetCostManager(currentEmployee, settings) &&
        !role_utils.isFleetAdmin(currentEmployee);
    final colors = Theme.of(context).appColors;

    final body = StreamBuilder<List<FleetCostLine>>(
      stream: _service.watchCostLines(from: _from, to: _to, limit: 500),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final lines = snapshot.data ?? [];

        double totalZar = 0;
        for (final l in lines) {
          totalZar += l.amountZar;
        }

        final byAsset = <String, double>{};
        for (final l in lines) {
          byAsset[l.assetName] = (byAsset[l.assetName] ?? 0) + l.amountZar;
        }
        final sortedAssets = byAsset.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final byCategory = _byCategory(lines);
        final sortedCategories = byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Column(
          children: [
            if (costMgrUx) const FleetReportsGuideBanner(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(
                      costMgrUx
                          ? 'This month'
                          : (_isYtd
                              ? 'Year to Date'
                              : monthFmt.format(_selectedMonth)),
                    ),
                    selected: !_isYtd,
                    selectedColor: kBrandOrange,
                    labelStyle:
                        TextStyle(color: !_isYtd ? Colors.white : null),
                    onSelected: (_) => setState(() => _isYtd = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(costMgrUx ? 'Year so far' : 'YTD'),
                    selected: _isYtd,
                    selectedColor: kBrandOrange,
                    labelStyle:
                        TextStyle(color: _isYtd ? Colors.white : null),
                    onSelected: (_) => setState(() => _isYtd = true),
                  ),
                  const Spacer(),
                  if (!_isYtd) ...[
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousMonth,
                    ),
                    if (!costMgrUx)
                      Text(
                        monthFmt.format(_selectedMonth),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                    ),
                  ],
                ],
              ),
            ),
            if (!_isYtd && costMgrUx)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  monthFmt.format(_selectedMonth),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: _isYtd
                              ? (costMgrUx
                                  ? 'Total year so far'
                                  : 'Total YTD')
                              : (costMgrUx
                                  ? 'Total this month'
                                  : 'Total This Month'),
                          value: 'R ${moneyFmt.format(totalZar)}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _KpiCard(
                          label: costMgrUx ? 'Cost entries' : 'Cost Lines',
                          value: lines.length.toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (sortedCategories.isNotEmpty) ...[
                    Text(
                      costMgrUx ? 'Spend by type' : 'Spend by Category',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sortedCategories.map((e) {
                        return Chip(
                          label: Text(
                            '${e.key.displayLabel}: R ${moneyFmt.format(e.value)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor:
                              kBrandOrange.withValues(alpha: 0.12),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (sortedAssets.isNotEmpty) ...[
                    Text(
                      costMgrUx ? 'Spend per machine' : 'Spend per Asset',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...sortedAssets.map((e) {
                      final pct =
                          totalZar > 0 ? e.value / totalZar : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  e.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'R ${moneyFmt.format(e.value)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct.toDouble(),
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation(
                                  kBrandOrange,
                                ),
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        costMgrUx ? 'All cost entries' : 'Cost Lines',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (lines.isNotEmpty)
                        TextButton.icon(
                          icon: _exporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.download,
                                  size: 18,
                                  color: kBrandOrange,
                                ),
                          label: Text(
                            costMgrUx ? 'Export CSV' : 'Export CSV',
                            style: const TextStyle(color: kBrandOrange),
                          ),
                          onPressed:
                              _exporting ? null : () => _export(lines),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        costMgrUx
                            ? 'No costs recorded for this period.\nEnter costs from the Costs tab first.'
                            : 'No cost lines for this period.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  else
                    ...lines.map(
                      (l) => _CostLineTile(
                        line: l,
                        dateFmt: dateFmt,
                        costMgrUx: costMgrUx,
                      ),
                    ),
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
      appBar: FleetAppBar(
        title: costMgrUx ? 'Spend Reports' : 'Cost Reports',
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
    final muted = Theme.of(context).appColors.textMuted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostLineTile extends StatelessWidget {
  const _CostLineTile({
    required this.line,
    required this.dateFmt,
    this.costMgrUx = false,
  });

  final FleetCostLine line;
  final DateFormat dateFmt;
  final bool costMgrUx;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    final linked = line.workNumber != null && line.workNumber!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            Expanded(
              child: Text(
                line.description,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'R ${line.amountZar.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${line.assetName} · ${line.category.displayLabel}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            Text(
              '${dateFmt.format(line.costDate)}'
              '${line.invoiceRef != null ? ' · Inv ${line.invoiceRef}' : ''}'
              '${line.supplier != null ? ' · ${line.supplier}' : ''}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            if (costMgrUx)
              Text(
                linked
                    ? 'Linked to job ${line.workNumber}'
                    : 'General cost (no job link)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: linked ? Colors.green.shade700 : muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}