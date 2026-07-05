import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../providers/current_employee_provider.dart';
import '../providers/persona_provider.dart';

/// Admin-only: pick a real employee to test UI gating as that role.
Future<void> showPersonaPickerDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _PersonaPickerDialog(ref: ref),
  );
}

class _PersonaPickerDialog extends ConsumerStatefulWidget {
  const _PersonaPickerDialog({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_PersonaPickerDialog> createState() => _State();
}

class _State extends ConsumerState<_PersonaPickerDialog> {
  String _query = '';
  bool _allowTestSubmissions = false;

  void _selectEmployee(Employee emp) {
    widget.ref.read(personaProvider.notifier).start(
          emp,
          allowTestSubmissions: _allowTestSubmissions,
        );
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Testing as ${emp.name}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildEmployeeList() {
    final employeesAsync = ref.watch(employeesStreamProvider);
    return employeesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (allEmployees) {
        var employees = allEmployees;
        if (_query.isNotEmpty) {
          employees = employees
              .where((e) =>
                  e.displayName.toLowerCase().contains(_query) ||
                  e.clockNo.contains(_query) ||
                  e.department.toLowerCase().contains(_query) ||
                  e.position.toLowerCase().contains(_query))
              .toList();
        }
        employees.sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));
        if (employees.isEmpty) {
          return const Center(child: Text('No employees match.'));
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: employees.length,
          itemBuilder: (_, i) {
            final emp = employees[i];
            return ListTile(
              dense: true,
              title: Text(emp.displayName),
              subtitle: Text('${emp.department} · ${emp.position}'),
              onTap: () => _selectEmployee(emp),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxDialogHeight = screen.height * 0.72;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: maxDialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text(
                'Test as employee',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'UI-only — your login, inbox, and push notifications stay as you. '
                      'Clears when the app restarts.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search employee',
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Allow test submissions',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Off = view only. On = writes stay as you with audit fields.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _allowTestSubmissions,
                          onChanged: (v) =>
                              setState(() => _allowTestSubmissions = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (maxDialogHeight * 0.45).clamp(140.0, 280.0),
                      ),
                      child: _buildEmployeeList(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}