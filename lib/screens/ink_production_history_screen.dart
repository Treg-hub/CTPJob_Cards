import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_production_run.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/role.dart' as role_utils;

/// Production run history (manager) — list of recorded batches. Tap a run to void
/// it (reverses every input + the output). Voiding into a finalised period is
/// admin-only (enforced by the closed-period guard).
class InkProductionHistoryScreen extends ConsumerWidget {
  const InkProductionHistoryScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _df = DateFormat('d MMM yyyy');

  Future<void> _void(BuildContext context, WidgetRef ref, InkProductionRun run,
      String outName) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void production run?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This reverses every input and the output '
                '(${_qty.format(run.outputQty)} $outName) for "${run.recipeName}".'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason *'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Void run')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a reason for the void.')));
      return;
    }
    final allowed =
        await confirmClosedPeriodOverride(context, ref, run.effectiveAt);
    if (!allowed || !context.mounted) return;
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).voidProductionRun(
            run.id,
            reason: reason,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Production run voided.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(inkProductionRunsProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final names = {for (final i in items) i.itemCode: i.displayName};
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Production History')),
      body: runsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (runs) => runs.isEmpty
            ? const Center(child: Text('No production runs yet.'))
            : ListView.separated(
                itemCount: runs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = runs[i];
                  final outName = names[r.outputItemCode] ?? r.outputItemCode;
                  final strike = r.voided
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null;
                  return ListTile(
                    leading: Icon(r.voided
                        ? Icons.cancel_outlined
                        : Icons.science_outlined),
                    title: Text(r.recipeName, style: strike),
                    subtitle: Text(
                      '${_df.format(r.effectiveAt)} · ${r.pots} pot(s)'
                      '${r.actorName != null ? ' · ${r.actorName}' : ''}'
                      '${r.voided ? ' · VOIDED' : ''}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${_qty.format(r.outputQty)} $outName',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: r.voided
                                    ? TextDecoration.lineThrough
                                    : null)),
                        if (isManager)
                          Text(_money.format(r.totalInputCost),
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    onTap: (isManager && !r.voided)
                        ? () => _void(context, ref, r, outName)
                        : null,
                  );
                },
              ),
      ),
    );
  }
}
