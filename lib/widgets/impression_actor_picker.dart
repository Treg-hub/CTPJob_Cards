import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee;
import '../models/employee.dart';
import '../theme/app_theme.dart';

enum ImpressionActorRole { mechanical, electrical, pressroom }

/// Manager/admin picker: who actually performed this step (historical accuracy).
class ImpressionActorPicker extends StatefulWidget {
  const ImpressionActorPicker({
    super.key,
    required this.role,
    required this.selectedClock,
    required this.onChanged,
    this.label,
  });

  final ImpressionActorRole role;
  final String? selectedClock;
  final ValueChanged<Employee?> onChanged;
  final String? label;

  @override
  State<ImpressionActorPicker> createState() => _ImpressionActorPickerState();
}

class _ImpressionActorPickerState extends State<ImpressionActorPicker> {
  List<Employee> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('employees').get();
      final all = snap.docs.map((d) {
        final m = d.data();
        return Employee(
          clockNo: (m['clockNo'] ?? m['clock_no'] ?? d.id).toString(),
          name: (m['name'] ?? m['displayName'] ?? '').toString(),
          position: (m['position'] ?? '').toString(),
          department: (m['department'] ?? '').toString(),
          isAdmin: m['isAdmin'] == true,
        );
      }).toList();

      final filtered = all.where(_matchesRole).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Always include current user if missing.
      final me = currentEmployee;
      if (me != null && !filtered.any((e) => e.clockNo == me.clockNo)) {
        filtered.insert(0, me);
      }

      if (mounted) {
        setState(() {
          _list = filtered;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  bool _matchesRole(Employee e) {
    final d = e.department.trim().toLowerCase();
    final p = e.position.trim().toLowerCase();
    switch (widget.role) {
      case ImpressionActorRole.mechanical:
        if (d != 'workshop') return false;
        if (p.contains('electric') && !p.contains('manager')) return false;
        return p.contains('mechanic') ||
            p == 'mechanic' ||
            (p.contains('manager') && !p.contains('electric'));
      case ImpressionActorRole.electrical:
        if (d != 'workshop') return false;
        if (p.contains('mechanic') || p.contains('mechanical')) {
          return p.contains('manager') && p.contains('electric');
        }
        return p.contains('electric') ||
            p.contains('electrician') ||
            (p.contains('manager') &&
                !p.contains('mechanic') &&
                !p.contains('mechanical'));
      case ImpressionActorRole.pressroom:
        return d == 'pressroom';
    }
  }

  String get _title {
    if (widget.label != null) return widget.label!;
    switch (widget.role) {
      case ImpressionActorRole.mechanical:
        return 'Done by (mechanical)';
      case ImpressionActorRole.electrical:
        return 'Tested by (electrical)';
      case ImpressionActorRole.pressroom:
        return 'Done by (pressroom)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_error != null) {
      return Text('Could not load staff list: $_error',
          style: TextStyle(color: scheme.error));
    }

    final value = widget.selectedClock;
    final clocks = _list.map((e) => e.clockNo).toSet();
    final effective = value != null && clocks.contains(value) ? value : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: effective,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _title,
              helperText: 'Managers/admin — pick who actually did the work',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_outline),
            ),
            items: [
              DropdownMenuItem(
                value: currentEmployee?.clockNo,
                child: Text(
                  'Me · ${currentEmployee?.name ?? "current user"}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ..._list
                  .where((e) => e.clockNo != currentEmployee?.clockNo)
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.clockNo,
                      child: Text(
                        '${e.name} · ${e.position} (${e.clockNo})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            ],
            onChanged: (clock) {
              if (clock == null) {
                widget.onChanged(null);
                return;
              }
              final match = _list.cast<Employee?>().firstWhere(
                    (e) => e?.clockNo == clock,
                    orElse: () => currentEmployee,
                  );
              widget.onChanged(match);
            },
          ),
          if (effective != null &&
              effective != currentEmployee?.clockNo)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Recording for another person (historical / on behalf of)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: kBrandOrange,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
