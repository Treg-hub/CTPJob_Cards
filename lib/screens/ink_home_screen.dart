import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/ink_toloul.dart';
import '../models/ink_stock_item.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/ink_daily_readings_banner.dart';
import 'ink_daily_readings_screen.dart';
import 'ink_ibc_register_screen.dart';
import 'ink_ibc_transfer_screen.dart';
import 'ink_production_run_screen.dart';
import 'ink_select_ibc_shipment_screen.dart';
import 'ink_receive_raw_material_screen.dart';
import 'ink_stock_item_detail_screen.dart';
import 'ink_toloul_recovery_screen.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';

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
    final inkSettings = ref.watch(inkSettingsProvider).valueOrNull;
    final readingsStatus =
        ref.watch(inkDailyReadingsStatusProvider).valueOrNull;
    final isManager = role_utils.isInkManager(
        ref.watch(currentEmployeeProvider).valueOrNull);
    InkStockItem? toloulItem;
    for (final i in itemsAsync.valueOrNull ?? <InkStockItem>[]) {
      if (i.isToloul) {
        toloulItem = i;
        break;
      }
    }
    final factoryLowThreshold = inkSettings?.toloulFactoryLowLitres ??
        kDefaultToloulFactoryLowLitres;

    return Scaffold(
      appBar: AppBar(title: const Text('Ink Factory')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          ScreenInsets.scrollBottomFullScreen(context),
        ),
        children: [
          _StockQtySummary(
            itemsAsync: itemsAsync,
            toloulItem: toloulItem,
            factoryLowThreshold: factoryLowThreshold,
          ),
          if (isManager) ...[
            const SizedBox(height: 12),
            _PulseManageCard(pulseUrl: _pulseInkUrl),
          ],
          if (readingsStatus != null && !readingsStatus.complete) ...[
            const SizedBox(height: 12),
            InkDailyReadingsBanner(status: readingsStatus),
          ],
          const SizedBox(height: 16),
          _sectionLabel(context, 'Capture'),
          const SizedBox(height: 8),
          _ActionGrid(actions: [
            _Action(Icons.local_shipping_outlined, 'Receive Stock',
                builder: () => const InkReceiveRawMaterialScreen()),
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
              onLongPress: (ctx) => _showFactoryTankLowThresholdDialog(ctx, ref),
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

  static Future<void> _showFactoryTankLowThresholdDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final settings = ref.read(inkSettingsProvider).valueOrNull;
    final current =
        settings?.toloulFactoryLowLitres ?? kDefaultToloulFactoryLowLitres;
    final ctrl = TextEditingController(
      text: current == current.roundToDouble()
          ? current.toInt().toString()
          : current.toString(),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toloul tank low alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Turn the summary card red when the ink-factory toloul tank '
              'drops below this level (litres). Long-press Toloul Recovery to change.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Low level (L)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final thresholdText = ctrl.text.trim();
    ctrl.dispose();
    if (saved != true || !context.mounted) return;
    final parsed = double.tryParse(thresholdText);
    if (parsed == null || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid non-negative number.')),
      );
      return;
    }
    try {
      await ref.read(inkServiceProvider).updateToloulFactoryLowThreshold(parsed);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Low level set to ${_qty.format(parsed)} L')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
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
    this.onLongPress,
  });
  final IconData icon;
  final String label;
  final Widget Function()? builder;
  final void Function(BuildContext context)? onLongPress;
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
        onLongPress: action.onLongPress != null
            ? () => action.onLongPress!(context)
            : null,
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
    required this.toloulItem,
    required this.factoryLowThreshold,
  });

  final AsyncValue<List<InkStockItem>> itemsAsync;
  final InkStockItem? toloulItem;
  final double factoryLowThreshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = itemsAsync.valueOrNull?.length ?? 0;
    final factoryBalance = toloulItem?.operationalBalance;
    final unit = toloulItem?.unit ?? 'LTS';
    final isLow = factoryBalance != null && factoryBalance < factoryLowThreshold;
    // Match Home quick-action tiles: flat tint + accent border; black body text.
    final accent = isLow ? kLowStockRed : kBrandOrange;
    final tileColor = accent.withValues(alpha: 0.12);
    final borderColor = accent.withValues(alpha: 0.45);
    final textColor = Theme.of(context).brightness == Brightness.light
        ? Colors.black87
        : scheme.onSurface;
    final tankValue = factoryBalance != null
        ? '${InkHomeScreen._qty.format(factoryBalance)} $unit'
        : '—';

    return Card(
      elevation: 0,
      color: tileColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock on hand',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '$count items',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Toloul tank',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  tankValue,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ],
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
    final displayQty =
        item.isToloul ? item.operationalBalance : item.currentBalance;
    final subtitle = item.isToloul
        ? 'Factory tank · consolidated ${InkHomeScreen._qty.format(item.currentBalance)} ${item.unit}'
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