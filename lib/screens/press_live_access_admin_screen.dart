import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/press_live_access.dart';
import '../services/employee_roster_cache.dart';
import '../services/press_live_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';

/// Factory Admin: who may open Press Live (`settings/press_live_access`).
///
/// Grant by department, position, and/or individual clock. Factory admins
/// always have access without being listed.
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
  Set<String> _departments = {};
  Set<String> _positions = {};
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
      final snap = await FirebaseFirestore.instance.doc(_docPath).get();
      final access = PressLiveAccess.fromMap(snap.data());
      final employees = await _roster.getRoster();
      if (!mounted) return;
      setState(() {
        _clockNos = access.clockNos.toSet();
        _departments = access.departments.toSet();
        _positions = access.positions.toSet();
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

  List<String> _uniqueField(String Function(Employee e) field) {
    final seen = <String, String>{};
    for (final e in _employees) {
      final raw = field(e).trim();
      if (raw.isEmpty) continue;
      seen.putIfAbsent(raw.toLowerCase(), () => raw);
    }
    final list = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _labelForClock(String clock) {
    for (final e in _employees) {
      if (e.clockNo == clock) {
        final name = e.name.trim();
        return name.isEmpty ? clock : '$name ($clock)';
      }
    }
    return clock;
  }

  Future<void> _pickLabels({
    required String title,
    required String searchHint,
    required List<String> options,
    required Set<String> current,
    required void Function(Set<String> next) onApply,
  }) async {
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No roster values loaded.')),
      );
      return;
    }
    final draft = Set<String>.from(current);
    final filterCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = filterCtrl.text.trim().toLowerCase();
          final list = options.where((v) {
            if (q.isEmpty) return true;
            return v.toLowerCase().contains(q);
          }).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    controller: filterCtrl,
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Icons.search, size: 20),
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
                        final v = list[i];
                        final on = draft.any(
                          (d) => d.toLowerCase() == v.toLowerCase(),
                        );
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(v, style: const TextStyle(fontSize: 14)),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) => setLocal(() {
                            draft.removeWhere(
                              (d) => d.toLowerCase() == v.toLowerCase(),
                            );
                            if (checked == true) draft.add(v);
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
                  onApply(draft);
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
      final payload = PressLiveAccess(
        clockNos: _clockNos.toList(),
        departments: _departments.toList(),
        positions: _positions.toList(),
      ).toFirestore();
      await FirebaseFirestore.instance.doc(_docPath).set({
        ...payload,
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

  Widget _chipSection({
    required String title,
    required String emptyLabel,
    required List<String> chips,
    required String Function(String) labelFor,
    required VoidCallback onEdit,
    required void Function(String) onDelete,
    required IconData icon,
    required String buttonLabel,
  }) {
    final muted = Theme.of(context).appColors.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        if (chips.isEmpty)
          Text(emptyLabel, style: TextStyle(fontSize: 13, color: muted))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in chips)
                InputChip(
                  label: Text(labelFor(c), style: const TextStyle(fontSize: 12)),
                  onDeleted: () => onDelete(c),
                ),
            ],
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: Icon(icon),
          label: Text(buttonLabel),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    final deptChips = _departments.toList()..sort();
    final posChips = _positions.toList()..sort();
    final peopleChips = _clockNos.toList()..sort();

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
                  'Grant a whole department (e.g. Pressroom), a position '
                  '(e.g. Foreman, Shift Leader), and/or named people. Anyone '
                  'matching any of those may open Press Live. Factory admins '
                  'always have access.',
                  style: TextStyle(fontSize: 13, color: muted, height: 1.35),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                _chipSection(
                  title: 'Departments',
                  emptyLabel: 'No departments selected.',
                  chips: deptChips,
                  labelFor: (s) => s,
                  onEdit: () => _pickLabels(
                    title: 'Select departments',
                    searchHint: 'Search department…',
                    options: _uniqueField((e) => e.department),
                    current: _departments,
                    onApply: (next) => setState(() => _departments = next),
                  ),
                  onDelete: (s) => setState(() => _departments.remove(s)),
                  icon: Icons.apartment_outlined,
                  buttonLabel: 'Add / edit departments',
                ),
                const SizedBox(height: 24),
                _chipSection(
                  title: 'Positions',
                  emptyLabel: 'No positions selected.',
                  chips: posChips,
                  labelFor: (s) => s,
                  onEdit: () => _pickLabels(
                    title: 'Select positions',
                    searchHint: 'Search position…',
                    options: _uniqueField((e) => e.position),
                    current: _positions,
                    onApply: (next) => setState(() => _positions = next),
                  ),
                  onDelete: (s) => setState(() => _positions.remove(s)),
                  icon: Icons.badge_outlined,
                  buttonLabel: 'Add / edit positions',
                ),
                const SizedBox(height: 24),
                _chipSection(
                  title: 'People',
                  emptyLabel: 'No people selected.',
                  chips: peopleChips,
                  labelFor: _labelForClock,
                  onEdit: _pickPeople,
                  onDelete: (c) => setState(() => _clockNos.remove(c)),
                  icon: Icons.person_add_alt_1_outlined,
                  buttonLabel: 'Add / edit people',
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
