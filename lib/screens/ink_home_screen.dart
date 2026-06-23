import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ink_stock_item.dart';
import '../providers/ink_provider.dart';
import 'ink_daily_readings_screen.dart';
import 'ink_ibc_register_screen.dart';
import 'ink_ibc_transfer_screen.dart';
import 'ink_production_run_screen.dart';
import 'ink_receive_ibc_screen.dart';
import 'ink_receive_raw_material_screen.dart';
import 'ink_stock_item_detail_screen.dart';
import 'ink_toloul_recovery_screen.dart';

/// Ink Factory module hub — operator capture only. Management, costing and
/// month-end workflows live in CTP Pulse (web).
class InkHomeScreen extends ConsumerWidget {
  const InkHomeScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');

  static const _pulseInkUrl = 'https://ctp-pulse.web.app/ink';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final inkMeterDone =
        ref.watch(inkTodayInkMeterDoneProvider).valueOrNull ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Ink Factory')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _StockQtySummary(itemsAsync: itemsAsync),
          const SizedBox(height: 12),
          _PulseManageCard(pulseUrl: _pulseInkUrl),
          if (!inkMeterDone) ...[
            const SizedBox(height: 12),
            const _MeterReminderBanner(),
          ],
          const SizedBox(height: 16),
          _sectionLabel(context, 'Capture'),
          const SizedBox(height: 8),
          _ActionGrid(actions: [
            _Action(Icons.local_shipping_outlined, 'Receive Stock',
                builder: () => const InkReceiveRawMaterialScreen()),
            _Action(Icons.propane_tank_outlined, 'Receive Ink (IBC)',
                builder: () => const InkReceiveIbcScreen()),
            _Action(Icons.speed_outlined, 'Meter Readings',
                builder: () => const InkDailyReadingsScreen()),
            _Action(Icons.swap_horiz_outlined, 'Consume IBC',
                builder: () => const InkIbcTransferScreen()),
            _Action(Icons.science_outlined, 'Production Run',
                builder: () => const InkProductionRunScreen()),
            _Action(Icons.recycling_outlined, 'Toloul Recovery',
                builder: () => const InkTolulRecoveryScreen()),
            _Action(Icons.inventory_2_outlined, 'IBC Register',
                builder: () => const InkIbcRegisterScreen()),
          ]),
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
                    children: [
                      for (final i in items) _StockTile(item: i),
                    ],
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

class _PulseManageCard extends StatelessWidget {
  const _PulseManageCard({required this.pulseUrl});
  final String pulseUrl;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(pulseUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open CTP Pulse.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.open_in_browser, color: scheme.primary),
        title: const Text('Management & costing'),
        subtitle: const Text(
          'Month-end, pending costs, recipes and reports — CTP Pulse',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context),
      ),
    );
  }
}

class _Action {
  const _Action(this.icon, this.label, {this.builder});
  final IconData icon;
  final String label;
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

class _StockQtySummary extends StatelessWidget {
  const _StockQtySummary({required this.itemsAsync});
  final AsyncValue<List<InkStockItem>> itemsAsync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                Text('Stock on hand',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer)),
                Text(
                  '$count items',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterReminderBanner extends StatelessWidget {
  const _MeterReminderBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const InkDailyReadingsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.speed, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Daily meter reading not captured yet today.',
                  style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.item});
  final InkStockItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(item.displayName),
      subtitle: Text(
        '${InkHomeScreen._qty.format(item.currentBalance)} ${item.unit}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => InkStockItemDetailScreen(itemCode: item.itemCode)),
      ),
    );
  }
}