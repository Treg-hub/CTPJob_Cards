import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_settings.dart';
import '../models/fleet_type.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';

/// Admin-only screen: fleet configuration (reporter departments, cost managers,
/// asset/work types, feature flag).
class FleetSettingsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const FleetSettingsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<FleetSettingsScreen> createState() =>
      _FleetSettingsScreenState();
}

class _FleetSettingsScreenState extends ConsumerState<FleetSettingsScreen> {
  final _service = FleetService();

  FleetSettings? _settings;
  List<String> _allDepartments = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();
    final empSnap =
        await FirebaseFirestore.instance.collection('employees').get();
    final departments = empSnap.docs
        .map((d) => d.data()['department'] as String? ?? '')
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (mounted) {
      setState(() {
        _settings = settings;
        _allDepartments = departments;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await _service.saveSettings(_settings!);
      ref.invalidate(fleetSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Settings saved.'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!role_utils.isFleetAdmin(currentEmployee)) {
      if (widget.embedded) return const Center(child: Text('Admin access required.'));
      return const Scaffold(body: Center(child: Text('Admin access required.')));
    }
    if (_loading) {
      if (widget.embedded) return const Center(child: CircularProgressIndicator());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final s = _settings!;

    final saveAction = _saving
        ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
        : TextButton(onPressed: _save, style: TextButton.styleFrom(foregroundColor: Colors.black), child: const Text('Save'));

    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Feature flag ──────────────────────────────────────────────
          _SectionHeader(title: 'Module', icon: Icons.toggle_on),
          SwitchListTile(
            title: const Text('Fleet Maintenance Enabled'),
            subtitle: const Text('Shows the Fleet tab for all eligible users'),
            value: s.fleetEnabled,
            onChanged: (v) =>
                setState(() => _settings = s.copyWith(fleetEnabled: v)),
          ),
          const Divider(),

          // ── Reporter departments ───────────────────────────────────────
          _SectionHeader(
              title: 'Reporter Departments',
              icon: Icons.people,
              subtitle:
                  'Employees in selected departments can report fleet issues'),
          ..._allDepartments.map((dept) {
            final selected = s.reporterDepartments.contains(dept);
            return CheckboxListTile(
              dense: true,
              title: Text(dept),
              value: selected,
              onChanged: (checked) {
                final updated = List<String>.from(s.reporterDepartments);
                if (checked == true) {
                  updated.add(dept);
                } else {
                  updated.remove(dept);
                }
                setState(
                    () => _settings = s.copyWith(reporterDepartments: updated));
              },
            );
          }),
          const Divider(),

          // ── Cost managers ─────────────────────────────────────────────
          _SectionHeader(
            title: 'Cost Managers',
            icon: Icons.attach_money,
            subtitle: 'Clock numbers allowed to enter and view cost lines',
          ),
          _ClockNoChipEditor(
            clockNos: s.costManagerClockNos,
            onChanged: (updated) =>
                setState(() => _settings = s.copyWith(costManagerClockNos: updated)),
          ),
          const Divider(),

          // ── Mechanics ─────────────────────────────────────────────────
          _SectionHeader(
            title: 'Mechanics',
            icon: Icons.precision_manufacturing,
            subtitle: 'Clock numbers with Mechanic access (log work, acknowledge/resolve issues)',
          ),
          _ClockNoChipEditor(
            clockNos: s.mechanicClockNos,
            onChanged: (updated) =>
                setState(() => _settings = s.copyWith(mechanicClockNos: updated)),
          ),
          const Divider(),

          // ── Asset types ────────────────────────────────────────────────
          _SectionHeader(title: 'Asset Types', icon: Icons.forklift),
          _TypeListSection(service: _service, kind: 'asset_type'),
          const Divider(),

          // ── Work types ─────────────────────────────────────────────────
          _SectionHeader(title: 'Work Types', icon: Icons.build),
          _TypeListSection(service: _service, kind: 'work_type'),

          const SizedBox(height: 80),
        ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [saveAction],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: FleetAppBar(
        title: 'Fleet Settings',
        actions: [saveAction],
      ),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon, this.subtitle});
  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: kBrandOrange),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 26),
              child: Text(subtitle!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clock-number chip editor with add/remove
// ---------------------------------------------------------------------------

class _ClockNoChipEditor extends StatefulWidget {
  const _ClockNoChipEditor({
    required this.clockNos,
    required this.onChanged,
  });
  final List<String> clockNos;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ClockNoChipEditor> createState() => _ClockNoChipEditorState();
}

class _ClockNoChipEditorState extends State<_ClockNoChipEditor> {
  final _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ...widget.clockNos.map((no) => Chip(
                  label: Text(no),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    final updated = List<String>.from(widget.clockNos)
                      ..remove(no);
                    widget.onChanged(updated);
                  },
                )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                decoration: const InputDecoration(
                  hintText: 'Add clock number',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white),
              onPressed: () {
                final no = _addCtrl.text.trim();
                if (no.isEmpty || widget.clockNos.contains(no)) return;
                widget.onChanged([...widget.clockNos, no]);
                _addCtrl.clear();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Type list (asset_type / work_type) with add/deactivate
// ---------------------------------------------------------------------------

class _TypeListSection extends ConsumerStatefulWidget {
  const _TypeListSection({required this.service, required this.kind});
  final FleetService service;
  final String kind;

  @override
  ConsumerState<_TypeListSection> createState() => _TypeListSectionState();
}

class _TypeListSectionState extends ConsumerState<_TypeListSection> {
  final _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _addType() async {
    final label = _addCtrl.text.trim();
    if (label.isEmpty) return;
    try {
      await widget.service.saveType(FleetType(
        kind: widget.kind,
        label: label,
        sortOrder: 99,
      ));
      _addCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StreamBuilder<List<FleetType>>(
          stream: widget.service.watchTypes(kind: widget.kind),
          builder: (context, snapshot) {
            final types = snapshot.data ?? [];
            if (types.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No types yet.', style: TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              children: types.map((t) {
                return ListTile(
                  dense: true,
                  title: Text(t.label),
                  trailing: IconButton(
                    icon: const Icon(Icons.archive_outlined, size: 20),
                    tooltip: 'Deactivate',
                    onPressed: () async {
                      await widget.service.deactivateType(t.id!);
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                decoration: InputDecoration(
                  hintText: 'New ${widget.kind == 'asset_type' ? 'asset' : 'work'} type',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandOrange, foregroundColor: Colors.white),
              onPressed: _addType,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
