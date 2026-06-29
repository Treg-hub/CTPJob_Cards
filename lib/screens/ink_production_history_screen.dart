import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;

/// Production run history — read-only on mobile. Void corrections on CTP Pulse
/// (`/ink/production`).
@Deprecated('Void production runs on CTP Pulse only — since 2026-06-29')
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
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Production History')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Read-only on mobile. To void a run, use CTP Pulse → Ink → Production History.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: runsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (runs) => runs.isEmpty
                  ? const Center(child: Text('No production runs yet.'))
                  : ListView.separated(
                      itemCount: runs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = runs[i];
                        final outName =
                            names[r.outputItemCode] ?? r.outputItemCode;
                        final strike = r.voided
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
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
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
