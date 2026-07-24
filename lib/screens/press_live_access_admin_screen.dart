import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/employee_roster_cache.dart';
import '../services/press_live_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';

/// Factory Admin: who may open Press Live (`settings/press_live_access.clock_nos`).
class PressLiveAccessAdminScreen extends StatefulWidget {
  const PressLiveAccessAdminScreen({super.key});

  @override
  State<PressLiveAccessAdminScreen> createState() =>
      _PressLiveAccessAdminScreenState();
}

class _PressLiveAccessAdminScreenState extends State<PressLiveAccessAdminScreen> {
  static const _docPath = 'settings/press_live_access';

  final _roster = EmployeeRosterCache.instance;
  List<Employee> _employees = [];
  Set<String> _clockNos = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap =
          await FirebaseFirestore.instance.doc(_docPath).get();
      final raw = snap.data()?['clock_nos'];
      final clocks = <String>{};
      if (raw is List) {
        for (final e in raw) {
          final s = e.toString().trim();
          if (s.isNotEmpty) clocks.add(s);
        }
      }
      final employees = await _roster.getRoster();
      if (!mounted) return;
      setState(() {
        _clockNos = clocks;
        _employees = employees;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _labelFor(String clock) {
    for (final e in _employees) {
      if (e.clockNo == clock) {
        final name = e.name.trim();
        return name.isEmpty ? clock : '$name ($clock)';
      }
    }
    return clock;
  }

  Future<void> _pickPeople() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No employees loaded.')),
      );
      return;
    }
    final draft = Set<String>.from(_clockNos);
    final filterCtrl = TextEditingController();
    final sorted = [..._employees]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = filterCtrl.text.trim().toLowerCase();
          final list = sorted.where((e) {
            if (q.isEmpty) return true;
            return e.name.toLowerCase().contains(q) ||
                e.clockNo.toLowerCase().contains(q) ||
                e.department.toLowerCase().contains(q) ||
                e.position.toLowerCase().contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Select people'),
            content: SizedBox(
              width: double.maxFinite,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    controller: filterCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search name, clock, department…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${draft.length} selected · ${list.length} shown',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).appColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final on = draft.contains(e.clockNo);
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(
                            e.name.isEmpty ? e.clockNo : e.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${e.clockNo} · ${e.department} · ${e.position}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              draft.add(e.clockNo);
                            } else {
                              draft.remove(e.clockNo);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setLocal(() => draft.clear()),
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _clockNos = draft);
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    filterCtrl.dispose();
  }

  Future<void> _save() async {
    if (!guardPersonaSubmit(context)) return;
    setState(() => _saving = true);
    try {
      final list = _clockNos.toList()..sort();
      await FirebaseFirestore.instance.doc(_docPath).set({
        'clock_nos': list,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      PressLiveService.instance.invalidateAccessCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Press Live access saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    final chips = _clockNos.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Press Live access'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: ScreenInsets.symmetricScroll(context),
              children: [
                Text(
                  'Who can view Press Live',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Clock numbers listed here may open Press Live and refresh the '
                  'snapshot. Factory admins always have access.',
                  style: TextStyle(fontSize: 13, color: muted, height: 1.35),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                if (chips.isEmpty)
                  Text(
                    'No people selected yet.',
                    style: TextStyle(fontSize: 13, color: muted),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in chips)
                        InputChip(
                          label: Text(_labelFor(c), style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setState(() => _clockNos.remove(c)),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickPeople,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add / edit people'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
    );
  }
}
