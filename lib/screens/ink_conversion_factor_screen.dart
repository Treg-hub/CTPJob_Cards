import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/persona_audit.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;

/// Manager screen: set the litres→kg conversion factor per meter-read item.
/// An item becomes "meter-read" once it has a factor (the four inks + gravure
/// binder). `kg = litres × kgPerLitre`.
class InkConversionFactorScreen extends ConsumerWidget {
  const InkConversionFactorScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, InkStockItem item,
      double current) async {
    if (!guardPersonaSubmit(context)) return;
    final ctrl =
        TextEditingController(text: current > 0 ? current.toString() : '');
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.displayName),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'kg per litre', helperText: 'kg = litres × factor'),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
              child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v > 0) {
      await ref.read(inkServiceProvider).saveConversionFactor(item.itemCode, v);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversion Factors')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final itemsAsync = ref.watch(inkStockItemsProvider);
    final factorsAsync = ref.watch(inkConversionFactorsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Conversion Factors')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          // Only active metered items (the 4 inks + gravure binder).
          final candidates = items.where((i) => i.metered && i.active).toList();
          final factors = factorsAsync.valueOrNull ?? {};
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Meter readings are entered in litres and converted to kg '
                    'using these factors. Items without a factor are not metered.'),
              ),
              for (final item in candidates)
                Builder(builder: (context) {
                  final f = factors[item.itemCode]?.kgPerLitre ?? 0;
                  return ListTile(
                    title: Text(item.displayName),
                    subtitle: Text(
                        f > 0 ? '$f kg/L' : 'Not set — not metered'),
                    trailing: OutlinedButton(
                      onPressed: () => _edit(context, ref, item, f),
                      child: Text(f > 0 ? 'Edit' : 'Set'),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
