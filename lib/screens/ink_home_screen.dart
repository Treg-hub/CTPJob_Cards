import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_tank_level.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/ink_daily_readings_banner.dart';
import '../widgets/ink_tank_fill_bar.dart';
import 'ink_daily_readings_screen.dart';
import 'ink_ibc_register_screen.dart';
import 'ink_ibc_transfer_screen.dart';
import 'ink_production_run_screen.dart';
import 'ink_select_ibc_shipment_screen.dart';
import 'ink_select_local_order_screen.dart';
import 'ink_stock_item_detail_screen.dart';
import 'ink_tank_levels_screen.dart';
import 'ink_toloul_recovery_screen.dart';
import '../utils/screen_insets.dart';
import '../widgets/ink_guide_banner.dart';

/// Ink Factory module hub — operator capture only. Management, costing and
/// month-end workflows live in CTP Pulse (web).
class InkHomeScreen extends ConsumerWidget {
  const InkHomeScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');

  static const _pulseInkUrl = 'https://ctp-pulse.web.app/ink';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Ink Factory');
    }

    final itemsAsync = ref.watch(inkStockItemsProvider);
    final tanksAsync = ref.watch(inkTankLevelsProvider);
    final readingsAsync = ref.watch(inkDailyReadingsStatusProvider);
    final readingsStatus = readingsAsync.valueOrNull;
    final isManager = role_utils.isInkManager(
        ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ink Factory'),
        actions: [
          IconButton(
            tooltip: 'Tank levels',
            icon: const Icon(Icons.propane_tank_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InkTankLevelsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(inkStockItemsProvider);
          ref.invalidate(inkSettingsProvider);
          ref.invalidate(inkTankLevelsProvider);
          await ref.read(inkStockItemsProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            ScreenInsets.scrollBottomFullScreen(context),
          ),
          children: [
            _StockQtySummary(
              itemsAsync: itemsAsync,
              tanksAsync: tanksAsync,
            ),
            if (isManager) ...[
              const SizedBox(height: 12),
              _PulseManageCard(pulseUrl: _pulseInkUrl),
            ],
            if (readingsStatus != null && !readingsStatus.complete) ...[
              const SizedBox(height: 12),
              InkDailyReadingsBanner(status: readingsStatus),
            ],
            const SizedBox(height: 8),
            const InkGuideBanner.home(),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Capture'),
            const SizedBox(height: 8),
            _ActionGrid(actions: [
              _Action(Icons.local_shipping_outlined, 'Receive Local',
                  builder: () => const InkSelectLocalOrderScreen()),
              _Action(Icons.propane_tank_outlined, 'Receive Ink (IBC)',
                  builder: () => const InkSelectIbcShipmentScreen()),
              _Action(Icons.speed_outlined, 'Meter Readings',
                  builder: () => const InkDailyReadingsScreen()),
              _Action(Icons.swap_horiz_outlined, 'Consume IBC',
                  builder: () => const InkIbcTransferScreen()),
              _Action(Icons.science_outlined, 'Production Run',
                  builder: () => const InkProductionRunScreen()),
              _Action(
                Icons.recycling_outlined,
                'Toloul Recovery',
                builder: () => const InkTolulRecoveryScreen(),
              ),
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
              loading: () => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading stock…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        ref.invalidate(inkStockItemsProvider);
                        ref.invalidate(inkSettingsProvider);
                        ref.invalidate(inkTankLevelsProvider);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load stock: $e'),
              ),
            ),
          ],
        ),
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
  const _Action(
    this.icon,
    this.label, {
    this.builder,
  });
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
  const _StockQtySummary({
    required this.itemsAsync,
    required this.tanksAsync,
  });

  final AsyncValue<List<InkStockItem>> itemsAsync;
  final AsyncValue<List<InkTankLevel>> tanksAsync;

  @override
  Widget build(BuildContext context) {
    final count = itemsAsync.valueOrNull?.length ?? 0;
    final tanks = tanksAsync.valueOrNull ?? const <InkTankLevel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stock on hand · $count items',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        if (tanksAsync.isLoading && tanks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cross = width >= 520 ? 3 : 2;
              final gap = 8.0;
              final cardW = (width - gap * (cross - 1)) / cross;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in tanks)
                    SizedBox(
                      width: cardW,
                      child: InkTankLevelCard(tank: t, compact: true),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.item});
  final InkStockItem item;

  @override
  Widget build(BuildContext context) {
    final displayQty =
        item.isToloul ? item.operationalBalance : item.currentBalance;
    final subtitle = item.isToloul
        ? 'Ledger · consolidated ${InkHomeScreen._qty.format(item.currentBalance)} ${item.unit}'
        : '${InkHomeScreen._qty.format(item.currentBalance)} ${item.unit}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(item.displayName),
      subtitle: Text(subtitle),
      trailing: Text(
        '${InkHomeScreen._qty.format(displayQty)} ${item.unit}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => InkStockItemDetailScreen(itemCode: item.itemCode)),
      ),
    );
  }
}
