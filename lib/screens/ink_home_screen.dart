import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;
import 'ink_adjustment_screen.dart';
import 'ink_conversion_factor_screen.dart';
import 'ink_corrections_screen.dart';
import 'ink_flagged_review_screen.dart';
import 'ink_ibc_transfer_screen.dart';
import 'ink_meter_point_entry_screen.dart';
import 'ink_meter_point_management_screen.dart';
import 'ink_meter_readings_grid_screen.dart';
import 'ink_meter_readings_screen.dart';
import 'ink_month_end_count_screen.dart';
import 'ink_month_end_report_screen.dart';
import 'ink_other_meter_screen.dart';
import 'ink_pending_costs_screen.dart';
import 'ink_production_history_screen.dart';
import 'ink_production_run_screen.dart';
import 'ink_receive_ibc_screen.dart';
import 'ink_receive_raw_material_screen.dart';
import 'ink_recipe_management_screen.dart';
import 'ink_revaluation_screen.dart';
import 'ink_stock_item_detail_screen.dart';
import 'ink_supplier_management_screen.dart';
import 'ink_toloul_recovery_screen.dart';

/// Ink Factory module hub — the landing screen for the production stock-inventory
/// module. Shows live stock-on-hand (from the ledger cache) and the data-entry
/// actions. Operator actions are open to any Ink Factory user; cost/value and
/// month-end actions are gated to managers (Phase 1 screens are stubbed for now).
class InkHomeScreen extends ConsumerWidget {
  const InkHomeScreen({super.key});

  static final _money = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);
  static final _qty = NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final isManager = role_utils.isInkManager(emp);
    final itemsAsync = ref.watch(inkStockItemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ink Factory')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _StockValueSummary(itemsAsync: itemsAsync),
          const SizedBox(height: 16),
          _sectionLabel(context, 'Capture'),
          const SizedBox(height: 8),
          _ActionGrid(actions: [
            _Action(Icons.local_shipping_outlined, 'Receive Stock',
                builder: () => const InkReceiveRawMaterialScreen()),
            _Action(Icons.propane_tank_outlined, 'Receive Ink (IBC)',
                builder: () => const InkReceiveIbcScreen()),
            _Action(Icons.straighten_outlined, 'Meter Readings',
                builder: () => const InkMeterReadingsScreen()),
            _Action(Icons.grid_on_outlined, 'Meter Grid',
                builder: () => const InkMeterReadingsGridScreen()),
            _Action(Icons.swap_horiz_outlined, 'IBC Transfer',
                builder: () => const InkIbcTransferScreen()),
            _Action(Icons.science_outlined, 'Production Run',
                builder: () => const InkProductionRunScreen()),
            _Action(Icons.recycling_outlined, 'Toloul Recovery',
                builder: () => const InkTolulRecoveryScreen()),
            _Action(Icons.water_outlined, 'Toloul Meters',
                builder: () => const InkMeterPointEntryScreen()),
            _Action(Icons.speed_outlined, 'Other Meter',
                builder: () => const InkOtherMeterScreen()),
          ]),
          if (isManager) ...[
            const SizedBox(height: 16),
            _sectionLabel(context, 'Manager'),
            const SizedBox(height: 8),
            _ActionGrid(actions: [
              _Action(Icons.store_outlined, 'Suppliers',
                  builder: () => const InkSupplierManagementScreen()),
              _Action(Icons.fact_check_outlined, 'Month-end Count',
                  builder: () => const InkMonthEndCountScreen()),
              _Action(Icons.tune_outlined, 'Stock Adjustment',
                  builder: () => const InkAdjustmentScreen()),
              _Action(Icons.payments_outlined, 'Pending Costs',
                  builder: () => const InkPendingCostsScreen()),
              _Action(Icons.summarize_outlined, 'Month-end Report',
                  builder: () => const InkMonthEndReportScreen()),
              _Action(Icons.menu_book_outlined, 'Recipes',
                  builder: () => const InkRecipeManagementScreen()),
              _Action(Icons.straighten, 'Conversion Factors',
                  builder: () => const InkConversionFactorScreen()),
              _Action(Icons.opacity, 'Toloul Meter Points',
                  builder: () => const InkMeterPointManagementScreen()),
              _Action(Icons.history, 'Production History',
                  builder: () => const InkProductionHistoryScreen()),
              _Action(Icons.price_change_outlined, 'Revaluation',
                  builder: () => const InkRevaluationScreen()),
              _Action(Icons.edit_note_outlined, 'Corrections',
                  builder: () => const InkCorrectionsScreen()),
              _Action(Icons.flag_outlined, 'Flagged',
                  builder: () => const InkFlaggedReviewScreen()),
            ]),
          ],
          const SizedBox(height: 20),
          _sectionLabel(context, 'Stock on hand'),
          const SizedBox(height: 4),
          itemsAsync.when(
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No stock items yet.')),
                  )
                : Column(
                    children: [for (final i in items) _StockTile(item: i)],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load stock: $e'),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _sectionLabel(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
      );
}

class _Action {
  const _Action(this.icon, this.label, {this.builder});
  final IconData icon;
  final String label;

  /// When set, tapping pushes this screen; otherwise shows a "later phase" hint.
  final Widget Function()? builder;
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions});
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in actions)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 24 - 16) / 3,
            child: _ActionCard(action: a),
          ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});
  final _Action action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (action.builder != null) {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => action.builder!()));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${action.label} — coming in a later phase')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(action.icon, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockValueSummary extends StatelessWidget {
  const _StockValueSummary({required this.itemsAsync});
  final AsyncValue<List<InkStockItem>> itemsAsync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = itemsAsync.valueOrNull
            ?.fold<double>(0, (sum, i) => sum + i.value) ??
        0;
    final count = itemsAsync.valueOrNull?.length ?? 0;
    return Card(
      color: scheme.primaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total stock value',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer)),
                Text(
                  InkHomeScreen._money.format(total),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Spacer(),
            Text('$count items',
                style: TextStyle(color: scheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.item});
  final InkStockItem item;

  IconData get _icon => switch (item.itemClass) {
        InkItemClass.ink => Icons.water_drop_outlined,
        InkItemClass.solvent => Icons.opacity_outlined,
        InkItemClass.manufactured => Icons.blender_outlined,
        InkItemClass.raw => Icons.inventory_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final negative = item.currentBalance < 0;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InkStockItemDetailScreen(itemCode: item.itemCode))),
      leading: Icon(_icon, color: scheme.primary),
      title: Text(item.displayName),
      subtitle: Text(
        '${InkHomeScreen._qty.format(item.currentBalance)} ${item.unit}'
        '  @ ${InkHomeScreen._money.format(item.weightedAverageCost)}',
        style: TextStyle(color: negative ? scheme.error : null),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(InkHomeScreen._money.format(item.value),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (negative)
            Text('negative', style: TextStyle(color: scheme.error, fontSize: 11)),
        ],
      ),
    );
  }
}
