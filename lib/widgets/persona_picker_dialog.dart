import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../providers/persona_provider.dart';
import '../services/firestore_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Test as employee'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow test submissions'),
              subtitle: const Text(
                'Off = view navigation only. On = writes stay as you with acting-as audit fields.',
                style: TextStyle(fontSize: 11),
              ),
              value: _allowTestSubmissions,
              onChanged: (v) => setState(() => _allowTestSubmissions = v),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 280,
              child: StreamBuilder<List<Employee>>(
                stream: FirestoreService().getEmployeesStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var employees = snapshot.data!;
                  if (_query.isNotEmpty) {
                    employees = employees
                        .where((e) =>
                            e.displayName.toLowerCase().contains(_query) ||
                            e.clockNo.contains(_query) ||
                            e.department.toLowerCase().contains(_query) ||
                            e.position.toLowerCase().contains(_query))
                        .toList();
                  }
                  employees.sort((a, b) =>
                      a.displayName.toLowerCase().compareTo(
                            b.displayName.toLowerCase(),
                          ));
                  if (employees.isEmpty) {
                    return const Center(child: Text('No employees match.'));
                  }
                  return ListView.builder(
                    itemCount: employees.length,
                    itemBuilder: (_, i) {
                      final emp = employees[i];
                      return ListTile(
                        dense: true,
                        title: Text(emp.displayName),
                        subtitle: Text('${emp.department} · ${emp.position}'),
                        onTap: () {
                          ref.read(personaProvider.notifier).start(
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
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}