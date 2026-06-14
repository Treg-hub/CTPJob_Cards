import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_recipe.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;

/// Phase 1f — Production Run. Operator picks a recipe and pot count (default 3,
/// 1/2 also allowed); the screen previews inputs consumed and output produced
/// (with an estimated cost from current WACs) and records the run: a
/// consumption per input + a manufacture of the output.
class InkProductionRunScreen extends ConsumerStatefulWidget {
  const InkProductionRunScreen({super.key});

  @override
  ConsumerState<InkProductionRunScreen> createState() => _State();
}

class _State extends ConsumerState<InkProductionRunScreen> {
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _qty = NumberFormat('#,##0.##');
  String? _recipeId;
  int _pots = 3;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit(InkRecipe recipe, Map<String, double> wacByItem) async {
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).recordProductionRun(
            recipe: recipe,
            pots: _pots,
            effectiveAt: _effectiveAt,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
            wacByItem: wacByItem,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Production run recorded.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(inkRecipesProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final byCode = {for (final i in items) i.itemCode: i};
    final wacByItem = {for (final i in items) i.itemCode: i.weightedAverageCost};
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    // Operators don't see cost — only managers.
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Production Run')),
      body: recipesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (recipes) {
          if (recipes.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text(
                      'No active recipes. A manager must define one '
                      '(Ink hub → Recipes).')),
            );
          }
          InkRecipe? recipe;
          for (final r in recipes) {
            if (r.id == _recipeId) recipe = r;
          }

          double totalInputCost = 0;
          if (recipe != null) {
            for (final l in recipe.inputs) {
              totalInputCost += l.qtyPerPot * _pots * (wacByItem[l.itemCode] ?? 0);
            }
          }
          final outputQty = (recipe?.outputPerPot ?? 0) * _pots;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _recipeId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Recipe', border: OutlineInputBorder()),
                items: [
                  for (final r in recipes)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _recipeId = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Pots: '),
                  const SizedBox(width: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3 (batch)')),
                    ],
                    selected: {_pots},
                    onSelectionChanged: (s) => setState(() => _pots = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text('Effective date: ${df.format(_effectiveAt)}'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    alignment: Alignment.centerLeft),
              ),
              if (recipe != null) ...[
                const SizedBox(height: 20),
                Text('Consumes', style: Theme.of(context).textTheme.titleMedium),
                for (final l in recipe.inputs)
                  _line(context, byCode[l.itemCode], l.qtyPerPot * _pots,
                      wacByItem[l.itemCode] ?? 0, isManager),
                const Divider(height: 24),
                Text('Produces', style: Theme.of(context).textTheme.titleMedium),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(byCode[recipe.outputItemCode]?.displayName ??
                      recipe.outputItemCode),
                  trailing: Text('${_qty.format(outputQty)} '
                      '${byCode[recipe.outputItemCode]?.unit ?? 'kg'}'),
                ),
                if (isManager)
                  Card(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Estimated input cost'),
                          Text(_money.format(totalInputCost),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _submit(recipe!, wacByItem),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Record production run'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _line(BuildContext context, InkStockItem? item, double qty, double wac,
      bool showMoney) {
    final negative = item != null && item.currentBalance < qty;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(item?.displayName ?? '?'),
      subtitle: negative
          ? Text('Only ${_qty.format(item.currentBalance)} ${item.unit} on hand',
              style: TextStyle(color: Theme.of(context).colorScheme.error))
          : null,
      trailing: Text('${_qty.format(qty)} ${item?.unit ?? ''}'
          '${showMoney ? '  ·  ${_money.format(qty * wac)}' : ''}'),
    );
  }
}
