import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_production_run.dart';
import '../models/ink_recipe.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';

/// Phase 1f — Production Run. Operator picks a recipe and pot count (default 3,
/// 1/2 also allowed); the screen previews inputs consumed and output produced
/// (quantities only — costing lives in CTP Pulse) and records the run.
///
/// Below the form the 10 most recent production runs are shown as a quick
/// history so the operator can confirm what was last made.
class InkProductionRunScreen extends ConsumerStatefulWidget {
  const InkProductionRunScreen({super.key});

  @override
  ConsumerState<InkProductionRunScreen> createState() => _State();
}

class _State extends ConsumerState<InkProductionRunScreen> {
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
    final runsAsync = ref.watch(inkProductionRunsProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final byCode = {for (final i in items) i.itemCode: i};
    final wacByItem = {for (final i in items) i.itemCode: i.weightedAverageCost};
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    final scheme = Theme.of(context).colorScheme;

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

          final outputQty = (recipe?.outputPerPot ?? 0) * _pots;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _recipeId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Recipe'),
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
                    onSelectionChanged: (s) =>
                        setState(() => _pots = s.first),
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
                Text('Consumes',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final l in recipe.inputs)
                  _line(context, byCode[l.itemCode], l.qtyPerPot * _pots),
                const Divider(height: 24),
                Text('Produces',
                    style: Theme.of(context).textTheme.titleMedium),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(byCode[recipe.outputItemCode]?.displayName ??
                      recipe.outputItemCode),
                  trailing: Text('${_qty.format(outputQty)} '
                      '${byCode[recipe.outputItemCode]?.unit ?? 'kg'}'),
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

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 4),
              Text('Recent Runs',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              ...runsAsync.when(
                loading: () =>
                    [const LinearProgressIndicator()],
                error: (_, __) => [],
                data: (runs) {
                  final recent = runs.take(10).toList();
                  if (recent.isEmpty) {
                    return [
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No production runs recorded yet.',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13),
                        ),
                      ),
                    ];
                  }
                  return [
                    for (final run in recent)
                      _RunTile(
                        run: run,
                        byCode: byCode,
                        qty: _qty,
                      ),
                  ];
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _line(BuildContext context, InkStockItem? item, double qty) {
    final negative = item != null && item.currentBalance < qty;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(item?.displayName ?? '?'),
      subtitle: negative
          ? Text(
              'Only ${_qty.format(item.currentBalance)} ${item.unit} on hand',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error))
          : null,
      trailing: Text('${_qty.format(qty)} ${item?.unit ?? ''}'),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({
    required this.run,
    required this.byCode,
    required this.qty,
  });

  static final _df = DateFormat('d MMM yy HH:mm');

  final InkProductionRun run;
  final Map<String, InkStockItem> byCode;
  final NumberFormat qty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outputName =
        byCode[run.outputItemCode]?.displayName ?? run.outputItemCode;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 12, top: 1),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${run.pots}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${run.recipeName} — ${qty.format(run.outputQty)} kg $outputName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _df.format(run.effectiveAt),
                    if (run.actorName != null) run.actorName!,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}