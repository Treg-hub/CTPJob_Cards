import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;

/// Manager screen: curate the supplier managed list. Add new suppliers and
/// toggle them active/inactive (inactive ones drop out of the receive picker
/// but stay on historical receipts, which store the supplier name).
class InkSupplierManagementScreen extends ConsumerWidget {
  const InkSupplierManagementScreen({super.key});

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add supplier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Supplier name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(inkServiceProvider).addSupplier(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Suppliers')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final suppliersAsync = ref.watch(inkAllSuppliersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (suppliers) => suppliers.isEmpty
            ? const Center(child: Text('No suppliers yet. Tap Add.'))
            : ListView.separated(
                itemCount: suppliers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = suppliers[i];
                  return SwitchListTile(
                    title: Text(
                      s.name,
                      style: TextStyle(
                        color:
                            s.active ? null : Theme.of(context).disabledColor,
                      ),
                    ),
                    subtitle: Text(s.active ? 'Active' : 'Inactive'),
                    value: s.active,
                    onChanged: s.id == null
                        ? null
                        : (v) => ref
                            .read(inkServiceProvider)
                            .setSupplierActive(s.id!, v),
                  );
                },
              ),
      ),
    );
  }
}
