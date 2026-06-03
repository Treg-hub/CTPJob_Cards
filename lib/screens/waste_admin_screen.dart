import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../utils/seed_waste_data.dart';
import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../models/waste_type.dart';
import '../models/contractor.dart';
import '../utils/formatters.dart';
import '../widgets/waste_app_bar.dart';

/// Basic Waste Admin screen.
/// Visible only to isWasteAdmin (currently clockNo == '22').
class WasteAdminScreen extends ConsumerStatefulWidget {
  const WasteAdminScreen({super.key});

  @override
  ConsumerState<WasteAdminScreen> createState() => _WasteAdminScreenState();
}

class _WasteAdminScreenState extends ConsumerState<WasteAdminScreen> {
  final WasteService _wasteService = WasteService();
  bool _seeding = false;
  bool _isProcessing = false; // for rate/type mutations

  // Phase 7: Pilot mode controls (simple clock list for controlled rollout)
  bool _pilotModeEnabled = false;
  String _pilotClockCsv = '';
  final TextEditingController _pilotCsvController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPilotConfig();
    // Consistency: drain any offline waste ops when admin opens controls (rates, types, flags)
    _wasteService.processOfflineWasteQueue();
  }

  @override
  void dispose() {
    _pilotCsvController.dispose();
    super.dispose();
  }

  Future<void> _loadPilotConfig() async {
    final pilotOn = await _wasteService.isPilotModeEnabled();
    final clocks = await _wasteService.getPilotClockNumbers();
    if (mounted) {
      setState(() {
        _pilotModeEnabled = pilotOn;
        _pilotClockCsv = clocks.join(',');
        _pilotCsvController.text = _pilotClockCsv;
      });
    }
  }

  Future<void> _savePilotConfig() async {
    setState(() => _isProcessing = true);
    try {
      await _wasteService.setPilotModeEnabled(_pilotModeEnabled);
      await _wasteService.setPilotClockNumbers(_pilotCsvController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilot configuration saved.'), backgroundColor: Colors.green),
        );
        await _loadPilotConfig();
        // Also log for pilot monitoring
        final actor = currentEmployee?.clockNo ?? 'admin';
        await _wasteService.logWasteUsage('admin_update_pilot_config', clockNo: actor);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pilot save failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runSeed() async {
    setState(() => _seeding = true);
    try {
      await seedWasteData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WasteTrack seed data inserted successfully!'), backgroundColor: Colors.green),
        );
        final actor = currentEmployee?.clockNo ?? 'admin';
        await _wasteService.logWasteUsage('admin_seed_data', clockNo: actor);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seeding failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  // --- Manage Types helpers (Phase 3 functional) ---
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

  Future<void> _addSubtype(WasteType type) async {
    final controller = TextEditingController();
    final subtype = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Subtype to ${type.mainType}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Subtype name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (subtype == null || subtype.isEmpty || type.id == null) return;

    setState(() => _isProcessing = true);
    try {
      await _wasteService.addSubtypeToType(type.id!, subtype);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added subtype "$subtype"'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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

    // Flatten subtypes for demo (in real: filter by selected main if wanted)
    final allSubtypes = types.expand((t) => t.subtypes.isNotEmpty ? t.subtypes : ['default']).toSet().toList();

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
                decoration: const InputDecoration(labelText: 'Subtype (or "default") *'),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select contractor, subtype and valid cost')));
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
      return const Scaffold(
        body: Center(child: Text('Access denied. Admin only.')),
      );
    }

    return Scaffold(
      appBar: WasteAppBar(
        title: 'WasteTrack Admin',
        isOnSite: null,
        actions: [
          if (SyncService().getQueuedWasteOperationCount() > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Queued offline: waste loads/items, photos, signatures, weighbridge updates, audits etc.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload, size: 16, color: Colors.orange),
                    const SizedBox(width: 2),
                    Text('${SyncService().getQueuedWasteOperationCount()}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Thresholds (read-only for now; settings doc editable via console or future form)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Deviation Alert Thresholds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Default: > 5% OR > 50 kg (from waste_settings/global)'),
                        const Text('Used by deviation.dart in load detail & reports.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Data Seeding (existing, improved state)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Data Seeding', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('One-time seed for development / first production setup:'),
                        const SizedBox(height: 8),
                        const Text('• 4 Contractors (Glenpak, Mondi, Industrial Scrap Waste, Mauser)'),
                        const Text('• 7 Main Waste Types + subtypes per spec'),
                        const Text('• Default deviation thresholds + notification config'),
                        const Text('• Sample rates for demo costing'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _seeding ? null : _runSeed,
                          icon: _seeding
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download),
                          label: Text(_seeding ? 'Seeding...' : 'Run WasteTrack Seed Data'),
                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreenDark),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ========== PHASE 3: MANAGE WASTE TYPES (now functional) ==========
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
                            Text('Manage Waste Types & Subtypes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface)),
                            IconButton(
                              icon: Icon(Icons.add_circle, color: appColors.wasteGreen),
                              onPressed: _addNewType,
                              tooltip: 'Add new main waste type',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Live from Firestore. Tap + on a type to add subtypes (arrayUnion).', style: TextStyle(color: onSurface)),
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
                                    subtitle: Text(t.subtypes.isEmpty ? 'No subtypes' : t.subtypes.join(', ')),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () => _addSubtype(t),
                                      tooltip: 'Add subtype',
                                    ),
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

                // ========== PHASE 3: MANAGE RATES (now functional) ==========
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Manage Rates (cost per kg by contractor + subtype)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Admin-only. Used for future report costing. Data in waste_rates.'),
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
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Current Rates (live):', style: TextStyle(fontWeight: FontWeight.w500)),
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
                                          return const Text('No rates set. Use seed or form above.', style: TextStyle(fontSize: 12, color: Colors.grey));
                                        }
                                        return Column(
                                          children: rates.take(10).map((r) {
                                            final cost = (r['cost_per_kg'] as num?)?.toDouble() ?? 0;
                                            return ListTile(
                                              dense: true,
                                              leading: const Icon(Icons.local_atm, size: 18),
                                              title: Text('${r['contractor_id'] ?? '?'} / ${r['subtype'] ?? '?'}'),
                                              trailing: Text(formatSACurrency(cost), style: const TextStyle(fontFamily: 'monospace')),
                                              subtitle: Text('by ${r['set_by'] ?? 'unknown'}'),
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
                ),
                const SizedBox(height: 16),

                // Future / remaining (updated to reflect Phase 3 progress)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Remaining Admin Features (future phases)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('• Manage Contractors & Collection Companies (basic add already in service)'),
                        Text('• Archived Loads recovery (waste_deleted_loads + soft delete flow)'),
                        Text('• Notification configuration (waste_settings)'),
                        Text('• Full rate override / edit / delete with confirmation dialogs'),
                        Text('• Bulk import/export of master data'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Rollout Safety Flag + Pilot Mode (PROD-CRITICAL-3 Phase 7)
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rollout Safety Flag + Pilot Mode (Production Control)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Master flag (safety valve) + optional pilot mode restricting access to a list of clock numbers only.'),
                        const SizedBox(height: 12),

                        // Master toggle (kept for safety valve)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isProcessing
                                    ? null
                                    : () async {
                                        setState(() => _isProcessing = true);
                                        try {
                                          final current = await _wasteService.getWasteMasterEnabled();
                                          await _wasteService.setWasteMasterEnabled(!current);
                                          if (mounted) {
                                            // ignore: use_build_context_synchronously
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Master flag set to ${!current}')),
                                            );
                                          }
                                        } finally {
                                          if (mounted) setState(() => _isProcessing = false);
                                        }
                                      },
                                child: const Text('Toggle Master WasteTrack Flag'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Pilot mode
                        SwitchListTile(
                          title: const Text('Enable Pilot Mode'),
                          subtitle: const Text('When on, only listed clock numbers can access WasteTrack (master must also be ON)'),
                          value: _pilotModeEnabled,
                          onChanged: (v) => setState(() => _pilotModeEnabled = v),
                          dense: true,
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _pilotCsvController,
                          decoration: const InputDecoration(
                            labelText: 'Allowed Clock Numbers (comma-separated)',
                            hintText: 'e.g. 22,105,207,301',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _pilotClockCsv = v,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _savePilotConfig,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Pilot Configuration'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Current pilot list: ${_pilotClockCsv.isEmpty ? '(none - all blocked in pilot mode)' : _pilotClockCsv}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tip: Include admin clocks (e.g. 22) to ensure recovery access. Changes take effect on next screen load / action.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
