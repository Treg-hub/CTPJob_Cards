import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../models/waste_settings.dart';
import '../theme/app_theme.dart';
import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../models/waste_type.dart';
import '../models/contractor.dart';
import '../utils/formatters.dart';
import '../widgets/waste_app_bar.dart';

/// Basic Waste Admin screen.
/// Visible only to isWasteAdmin (Employee.isAdmin == true).
class WasteAdminScreen extends ConsumerStatefulWidget {
  /// When [embedded] is true the screen skips its own Scaffold/AppBar so it
  /// can live inside a TabBarView in WasteHomeScreen.
  final bool embedded;
  const WasteAdminScreen({super.key, this.embedded = false});

  @override
  ConsumerState<WasteAdminScreen> createState() => _WasteAdminScreenState();
}

class _WasteAdminScreenState extends ConsumerState<WasteAdminScreen> {
  final WasteService _wasteService = WasteService();
  bool _isProcessing = false;
  bool _wasteEnabled = true;
  WasteSettings? _wasteSettings;
  bool _settingsSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _wasteService.processOfflineWasteQueue();
  }

  Future<void> _loadSettings() async {
    final settings = await _wasteService.getWasteSettings();
    if (mounted) {
      setState(() {
        _wasteSettings = settings;
        _wasteEnabled = settings.wasteEnabled;
      });
    }
  }

  Future<void> _savePermissions() async {
    if (_wasteSettings == null) return;
    setState(() => _settingsSaving = true);
    try {
      await _wasteService.saveWasteSettings(_wasteSettings!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions saved.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _settingsSaving = false);
    }
  }

  // --- Manage Types helpers ---
  Future<void> _addNewType() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Waste Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Main Type Name (e.g. Hazardous Waste)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      await _wasteService.createWasteType(WasteType(mainType: result));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created type: $result'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- Manage Rates helpers (Phase 3 functional, simple map based) ---
  Future<void> _showSetRateDialog(List<Contractor> contractors, List<WasteType> types) async {
    String? contractorId;
    String? subtype;
    double cost = 0;
    final costCtrl = TextEditingController();

    final allSubtypes = types.map((t) => t.mainType).toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDState) {
        return AlertDialog(
          title: const Text('Set Contractor Rate (per kg)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: contractorId,
                items: contractors.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setDState(() => contractorId = v),
                decoration: const InputDecoration(labelText: 'Contractor *'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: subtype,
                items: allSubtypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setDState(() => subtype = v),
                decoration: const InputDecoration(labelText: 'Waste Type *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cost per kg (R) *'),
                onChanged: (v) => cost = double.tryParse(v) ?? 0,
              ),
              const SizedBox(height: 8),
              const Text('Rates are additive for audit. Used in future reports costing.', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (contractorId == null || subtype == null || cost <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select contractor, waste type and valid cost')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save Rate'),
            ),
          ],
        );
      }),
    );

    if (ok != true || contractorId == null || subtype == null) return;

    setState(() => _isProcessing = true);
    try {
      final actor = currentEmployee?.name ?? currentEmployee?.clockNo ?? 'admin';
      await _wasteService.setRate(
        contractorId: contractorId!,
        subtype: subtype!,
        costPerKg: cost,
        setBy: actor,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rate saved: R${cost.toStringAsFixed(2)}/kg'), backgroundColor: Colors.green),
        );
        final actor = currentEmployee?.clockNo ?? 'admin';
        await _wasteService.logWasteUsage('admin_set_rate', clockNo: actor, metadata: {'contractorId': contractorId, 'subtype': subtype});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = role_utils.isWasteAdmin(currentEmployee);

    if (!isAdmin) {
      if (widget.embedded) return const Center(child: Text('Access denied. Admin only.'));
      return const Scaffold(
        body: Center(child: Text('Access denied. Admin only.')),
      );
    }

    final bodyContent = _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Master enable / disable toggle ─────────────────────────
                Card(
                  child: SwitchListTile(
                    title: const Text('WasteTrack Enabled', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_wasteEnabled ? 'System is live — loads, weighbridge and reports are active.' : 'System disabled. Guards cannot submit loads.'),
                    value: _wasteEnabled,
                    activeThumbColor: Theme.of(context).appColors.wasteGreen,
                    onChanged: (v) async {
                      setState(() {
                        _wasteEnabled = v;
                        _wasteSettings = (_wasteSettings ?? WasteSettings.defaults)
                            .copyWith(wasteEnabled: v);
                      });
                      await _wasteService.saveWasteSettings(
                          _wasteSettings!);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Deviation thresholds (read-only; editable via Firestore console)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Deviation Alert Thresholds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Default: > 5% OR > 50 kg (from waste_settings/global)'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Permissions ───────────────────────────────────────────────
                if (_wasteSettings != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Permissions',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              _settingsSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : TextButton(
                                      onPressed: _savePermissions,
                                      child: const Text('Save')),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Clock numbers that control access to each part of Waste. '
                            'Add a clock number to give that person the role.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),

                          // Security Managers
                          const Text('Security Managers',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(
                            'Can schedule loads, access weighbridge, view reports',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ..._ClockNumberChips(
                            clockNos: _wasteSettings!.managerClockNos,
                            hintText: 'Add manager clock no.',
                            onChanged: (updated) => setState(() =>
                                _wasteSettings = _wasteSettings!
                                    .copyWith(managerClockNos: updated)),
                          ).build(context),

                          const SizedBox(height: 16),

                          // Security Guards
                          const Text('Security Guards',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(
                            'Can begin collections, record items, capture signatures',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ..._ClockNumberChips(
                            clockNos: _wasteSettings!.guardClockNos,
                            hintText: 'Add guard clock no.',
                            onChanged: (updated) => setState(() =>
                                _wasteSettings = _wasteSettings!
                                    .copyWith(guardClockNos: updated)),
                          ).build(context),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // ── Manage Waste Types ─────────────────────────────────────────
                Builder(builder: (context) {
                  final appColors = Theme.of(context).appColors;
                  final surfaceBg = appColors.wasteGreenSurface;
                  final onSurface = onColor(surfaceBg);
                  return Card(
                  color: surfaceBg,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Manage Waste Types', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface)),
                            IconButton(
                              icon: Icon(Icons.add_circle, color: appColors.wasteGreen),
                              onPressed: _addNewType,
                              tooltip: 'Add new waste type',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Live from Firestore. Tap + to add a new type. Link types to contractors in the contractor settings.', style: TextStyle(color: onSurface)),
                        const SizedBox(height: 12),
                        StreamBuilder<List<WasteType>>(
                          stream: _wasteService.watchWasteTypes(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)));
                            }
                            if (snap.hasError) {
                              return Text('Error loading types: ${snap.error}', style: const TextStyle(color: Colors.red));
                            }
                            final types = snap.data ?? [];
                            if (types.isEmpty) {
                              return const Text('No types yet. Run seed or add one above.');
                            }
                            return Column(
                              children: types.map((t) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(t.mainType, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
                }),
                const SizedBox(height: 16),

                // ── Manage Rates ───────────────────────────────────────────────
                Builder(builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final ratesBg = isDark ? const Color(0xFF2D2200) : Colors.amber.shade50;
                  final ratesOn = onColor(ratesBg);
                  return Card(
                  color: ratesBg,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manage Rates (cost per kg by contractor + subtype)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ratesOn)),
                        const SizedBox(height: 4),
                        Text('Admin-only. Used for future report costing. Data in waste_rates.', style: TextStyle(color: ratesOn)),
                        const SizedBox(height: 12),
                        StreamBuilder<List<Contractor>>(
                          stream: _wasteService.watchContractors(),
                          builder: (context, cSnap) {
                            return StreamBuilder<List<WasteType>>(
                              stream: _wasteService.watchWasteTypes(),
                              builder: (context, tSnap) {
                                final contractors = cSnap.data ?? [];
                                final types = tSnap.data ?? [];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: (contractors.isEmpty || types.isEmpty)
                                          ? null
                                          : () => _showSetRateDialog(contractors, types),
                                      icon: const Icon(Icons.attach_money),
                                      label: const Text('Set New Rate'),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800], foregroundColor: Colors.black),
                                    ),
                                    const SizedBox(height: 12),
                                    Text('Current Rates (live):', style: TextStyle(fontWeight: FontWeight.w500, color: ratesOn)),
                                    StreamBuilder<List<Map<String, dynamic>>>(
                                      stream: _wasteService.watchRates(),
                                      builder: (context, rSnap) {
                                        if (rSnap.connectionState == ConnectionState.waiting) {
                                          return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
                                        }
                                        if (rSnap.hasError) {
                                          return Text('Rates error: ${rSnap.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
                                        }
                                        final rates = rSnap.data ?? [];
                                        if (rates.isEmpty) {
                                          return Text('No rates set. Use seed or form above.', style: TextStyle(fontSize: 12, color: ratesOn.withValues(alpha: 0.6)));
                                        }
                                        return Column(
                                          children: rates.take(10).map((r) {
                                            final cost = (r['cost_per_kg'] as num?)?.toDouble() ?? 0;
                                            final cId = r['contractor_id'] as String? ?? '';
                                            final cName = contractors.firstWhere(
                                              (c) => c.id == cId,
                                              orElse: () => Contractor(name: cId.isEmpty ? '?' : cId),
                                            ).name;
                                            return ListTile(
                                              dense: true,
                                              leading: Icon(Icons.local_atm, size: 18, color: ratesOn),
                                              title: Text('$cName / ${r['subtype'] ?? '?'}', style: TextStyle(color: ratesOn)),
                                              trailing: Text(formatSACurrency(cost), style: TextStyle(fontFamily: 'monospace', color: ratesOn)),
                                              subtitle: Text('by ${r['set_by'] ?? 'unknown'}', style: TextStyle(color: ratesOn.withValues(alpha: 0.7))),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
                }),
              ],
            );

    if (widget.embedded) return bodyContent;

    return Scaffold(
      appBar: WasteAppBar(
        title: 'WasteTrack Admin',
        isOnSite: null,
        actions: [
          if (SyncService().getQueuedWasteOperationCount() > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_upload, size: 16, color: Colors.orange),
                const SizedBox(width: 2),
                Text('${SyncService().getQueuedWasteOperationCount()}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ]),
            ),
        ],
      ),
      body: bodyContent,
    );
  }
}

// ---------------------------------------------------------------------------
// Clock number chips with add / remove (mirrors _CostManagerChips in fleet)
// ---------------------------------------------------------------------------

class _ClockNumberChips {
  _ClockNumberChips({
    required this.clockNos,
    required this.hintText,
    required this.onChanged,
  });

  final List<String> clockNos;
  final String hintText;
  final ValueChanged<List<String>> onChanged;

  List<Widget> build(BuildContext context) {
    final addCtrl = TextEditingController();
    final green = Theme.of(context).appColors.wasteGreen;
    return [
      Wrap(
        spacing: 8,
        children: [
          ...clockNos.map((no) => Chip(
                label: Text(no),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  final updated = List<String>.from(clockNos)..remove(no);
                  onChanged(updated);
                },
              )),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: addCtrl,
              decoration: InputDecoration(
                hintText: hintText,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: green, foregroundColor: Colors.white),
            onPressed: () {
              final no = addCtrl.text.trim();
              if (no.isEmpty || clockNos.contains(no)) return;
              final updated = [...clockNos, no];
              onChanged(updated);
              addCtrl.clear();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ];
  }
}
