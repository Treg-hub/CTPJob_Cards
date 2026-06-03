import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../models/waste_load.dart';
import '../utils/formatters.dart';
import '../widgets/waste_app_bar.dart';
import '../utils/deviation.dart';

/// Waste Reports screen (Phase 3/6 enhanced).
/// Uses real data from WasteService (loads). PDF + CSV export.
/// Costs shown only to Waste Admins (via existing role check).
/// CSV implemented with pure Dart (no extra packages needed; Excel would require pubspec edit - see comment).
class WasteReportsScreen extends ConsumerStatefulWidget {
  /// When [embedded] is true the screen skips its own Scaffold/AppBar so it
  /// can live inside a TabBarView in WasteHomeScreen.
  final bool embedded;
  const WasteReportsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<WasteReportsScreen> createState() => _WasteReportsScreenState();
}

class _WasteReportsScreenState extends ConsumerState<WasteReportsScreen> {
  final WasteService _wasteService = WasteService();
  List<WasteLoad> _loads = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRealData();
  }

  Future<void> _loadRealData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Drain queued creates/weighbridges/photos first so reports reflect the latest offline work
      await _wasteService.processOfflineWasteQueue();
      // Pull recent loads (real data). For full monthly would add date filters to service.
      final data = await _wasteService.watchLoads(limit: 200).first;
      if (mounted) {
        setState(() {
          _loads = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  double get _totalWeight {
    // Uses actual weighbridge when recorded (preferred post-entry), falls back to stored recordedWeightKg (from create).
    return _loads.fold(0.0, (sum, l) {
      if (l.actualWeighbridgeWeightKg != null && l.actualWeighbridgeWeightKg! > 0) {
        return sum + l.actualWeighbridgeWeightKg!;
      }
      if (l.recordedWeightKg > 0) return sum + l.recordedWeightKg;
      return sum;
    });
  }

  int get _deviationCount {
    // Real calculation using the same util as the weighbridge entry screen (5% or 50kg thresholds).
    return _loads.where((l) {
      final actual = l.actualWeighbridgeWeightKg;
      if (actual == null || actual <= 0) return false;
      final recorded = l.recordedWeightKg > 0 ? l.recordedWeightKg : actual;
      final res = calculateDeviation(recordedWeightKg: recorded, actualWeightKg: actual);
      return res.isDeviation;
    }).length;
  }

  bool get _isAdmin => role_utils.isWasteAdmin(currentEmployee);

  // PDF export (real deviation using shared util + recorded/actual weights)
  Future<void> _exportPdf() async {
    final doc = pw.Document();
    final now = DateTime.now();

    final tableData = _loads.take(20).map((l) {
      final actual = l.actualWeighbridgeWeightKg;
      String devStr = '—';
      if (actual != null && actual > 0) {
        final rec = l.recordedWeightKg > 0 ? l.recordedWeightKg : actual;
        final res = calculateDeviation(recordedWeightKg: rec, actualWeightKg: actual);
        devStr = res.isDeviation ? '⚠️ ${res.variancePercent.toStringAsFixed(1)}%' : 'OK';
      }
      return [
        l.loadNumber,
        l.mainWasteType,
        formatSAWeight(actual ?? l.recordedWeightKg),
        l.status.value,
        devStr,
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('WasteTrack Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Generated: ${formatSADateTime(now)}', style: pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 16),
            pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Total Loads in view: ${_loads.length}'),
            pw.Text('Total Weight: ${formatSAWeight(_totalWeight)}'),
            pw.Text('Loads triggering deviation: $_deviationCount (5% or 50 kg)'),
            if (_isAdmin) pw.Text('Cost data: Requires linked rates + item aggregation (future)'),
            pw.SizedBox(height: 12),
            pw.Text('Recent Loads (sample)', style: pw.TextStyle(fontSize: 12)),
            pw.TableHelper.fromTextArray(
              headers: ['Load #', 'Type', 'Weight (kg)', 'Status', 'Deviation'],
              data: tableData.isNotEmpty ? tableData : [['(no data)', '', '', '', '']],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Deviation rule: >5% OR >50 kg absolute (per WasteTrack spec).', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          ],
        ),
      ),
    );

    try {
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/wastetrack-report-${now.millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'WasteTrack Report'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // CSV export (Phase 3/6): Pure Dart implementation, no external package required.
  // Excel (.xlsx) would need 'excel' package + pubspec.yaml edit (forbidden for this agent per safety rules).
  // CSV is practical, opens in Excel/Google Sheets, and is safe.
  Future<void> _exportCsv() async {
    if (_loads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Load Number,Main Type,Date,Contractor ID,Status,Driver,Vehicle,Recorded kg,Actual Weighbridge kg,Variance kg,Variance %,Deviation?,Weighbridge #,Notes');

    for (final l in _loads) {
      final dateStr = formatSADate(l.dateTime);
      final actual = l.actualWeighbridgeWeightKg;
      final recorded = l.recordedWeightKg;
      String varKg = '', varPct = '', isDev = 'No';
      if (actual != null && actual > 0) {
        final rec = recorded > 0 ? recorded : actual;
        final res = calculateDeviation(recordedWeightKg: rec, actualWeightKg: actual);
        varKg = res.varianceKg.toStringAsFixed(1);
        varPct = res.variancePercent.toStringAsFixed(1);
        isDev = res.isDeviation ? 'YES' : 'No';
      }
      final w = actual?.toStringAsFixed(1) ?? (recorded > 0 ? recorded.toStringAsFixed(1) : '');
      // Escape quotes/commas minimally for CSV
      String esc(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
      buffer.writeln([
        esc(l.loadNumber),
        esc(l.mainWasteType),
        esc(dateStr),
        esc(l.contractorId),
        esc(l.status.value),
        esc(l.driverName),
        esc(l.vehicleReg),
        esc(recorded > 0 ? recorded.toStringAsFixed(1) : ''),
        esc(w),
        esc(varKg),
        esc(varPct),
        esc(isDev),
        esc(l.weighbridgeNumber),
        esc(l.notes),
      ].join(','));
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/wastetrack-report-${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'WasteTrack CSV Report (open in Excel)'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV exported & shared'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV export failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin;

    // Action buttons — shown in AppBar when standalone, or inline row when embedded.
    final actionButtons = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _isLoading ? null : _exportPdf, tooltip: 'Export PDF'),
        IconButton(icon: const Icon(Icons.table_chart), onPressed: _isLoading ? null : _exportCsv, tooltip: 'Export CSV'),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRealData, tooltip: 'Refresh'),
      ],
    );

    final bodyContent = Column(
      children: [
        if (widget.embedded) actionButtons,
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text('Failed to load report data:\n$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadRealData, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRealData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Live Summary (from Firestore)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              Text('Loads in view: ${_loads.length}'),
                              Text('Total Weight (weighbridge where recorded): ${formatSAWeight(_totalWeight)}'),
                              if (isAdmin)
                                const Text('Cost estimates: Requires rates + full item weight aggregation (future hardening)')
                              else
                                const Text('Cost data hidden (Admin role required)'),
                              Text('Loads triggering deviation (>5% or >50 kg): $_deviationCount'),
                              const SizedBox(height: 8),
                              const Text(
                                'Deviation calculated with shared util (same as weighbridge entry screen). Exports now include variance columns.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF616161)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _exportPdf,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Export PDF'),
                              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreenDark),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _exportCsv,
                              icon: const Icon(Icons.download),
                              label: const Text('Export CSV'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Excel note (per task - cannot add package)
                      const Text(
                        'Excel (.xlsx) export not available: would require adding the "excel" package in pubspec.yaml (outside allowed edit scope for safety). CSV is fully functional and opens directly in Excel/Sheets.',
                        style: TextStyle(color: Color(0xFF616161), fontSize: 12),
                      ),
                      const SizedBox(height: 24),
                      const Text('Recent Loads (live data)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_loads.isEmpty)
                        const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No loads found. Create some via Waste home.')))
                      else
                        ..._loads.take(20).map((load) {
                          final actual = load.actualWeighbridgeWeightKg;
                          Widget trailing = Text(
                            actual != null ? formatSAWeight(actual) : (load.recordedWeightKg > 0 ? formatSAWeight(load.recordedWeightKg) : '—'),
                            style: const TextStyle(fontFamily: 'monospace'),
                          );
                          if (actual != null && actual > 0) {
                            final rec = load.recordedWeightKg > 0 ? load.recordedWeightKg : actual;
                            final res = calculateDeviation(recordedWeightKg: rec, actualWeightKg: actual);
                            if (res.isDeviation) {
                              trailing = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                                  const SizedBox(width: 4),
                                  Text(formatSAWeight(actual), style: const TextStyle(fontFamily: 'monospace', color: Colors.red)),
                                ],
                              );
                            }
                          }
                          return Card(
                            child: ListTile(
                              title: Text('${load.loadNumber} — ${load.mainWasteType}'),
                              subtitle: Text('${formatSADate(load.dateTime)} • ${load.driverName} • ${load.status.value}'),
                              trailing: trailing,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
        ),  // Expanded
      ],
    ); // bodyContent Column

    if (widget.embedded) return bodyContent;

    return Scaffold(
      appBar: WasteAppBar(
        title: 'Waste Reports',
        isOnSite: currentEmployee?.isOnSite,
        actions: [
          if (SyncService().getQueuedWasteOperationCount() > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_upload, size: 16, color: Colors.orange),
                const SizedBox(width: 2),
                Text('${SyncService().getQueuedWasteOperationCount()}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ]),
            ),
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _isLoading ? null : _exportPdf, tooltip: 'Export PDF'),
          IconButton(icon: const Icon(Icons.table_chart), onPressed: _isLoading ? null : _exportCsv, tooltip: 'Export CSV'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRealData, tooltip: 'Refresh'),
        ],
      ),
      body: bodyContent,
    );
  }
}
