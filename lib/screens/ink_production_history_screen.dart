import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/ink_provider.dart';

/// Production run history (manager) — list of recorded batches.
class InkProductionHistoryScreen extends ConsumerWidget {
  const InkProductionHistoryScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _df = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(inkProductionRunsProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final names = {for (final i in items) i.itemCode: i.displayName};

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
                  return ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: Text(r.recipeName),
                    subtitle: Text(
                      '${_df.format(r.effectiveAt)} · ${r.pots} pot(s)'
                      '${r.actorName != null ? ' · ${r.actorName}' : ''}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            '${_qty.format(r.outputQty)} '
                            '${names[r.outputItemCode] ?? r.outputItemCode}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(_money.format(r.totalInputCost),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
