import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ink_provider.dart';

/// Manager screen: curate the auxiliary toloul meter points (no stock impact).
/// Each point links to Toloul Recovery or Toloul Usage; month-end totals each
/// group.
class InkMeterPointManagementScreen extends ConsumerWidget {
  const InkMeterPointManagementScreen({super.key});

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var linkage = 'usage';
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add meter point'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: linkage,
                decoration: const InputDecoration(labelText: 'Linked to'),
                items: const [
                  DropdownMenuItem(
                      value: 'recovery', child: Text('Toloul Recovery')),
                  DropdownMenuItem(value: 'usage', child: Text('Toloul Usage')),
                ],
                onChanged: (v) => setLocal(() => linkage = v ?? 'usage'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (added == true && controller.text.trim().isNotEmpty) {
      await ref.read(inkServiceProvider).addMeterPoint(controller.text, linkage);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointsAsync = ref.watch(inkAllMeterPointsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Toloul Meter Points')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: pointsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (points) => points.isEmpty
            ? const Center(child: Text('No meter points yet. Tap Add.'))
            : ListView.separated(
                itemCount: points.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = points[i];
                  return SwitchListTile(
                    title: Text(p.name,
                        style: TextStyle(
                            color: p.active
                                ? null
                                : Theme.of(context).disabledColor)),
                    subtitle: Text(p.linkageLabelText),
                    value: p.active,
                    onChanged: p.id == null
                        ? null
                        : (v) => ref
                            .read(inkServiceProvider)
                            .setMeterPointActive(p.id!, v),
                  );
                },
              ),
      ),
    );
  }
}
