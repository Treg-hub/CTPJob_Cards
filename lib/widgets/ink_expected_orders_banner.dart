import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/ink_provider.dart';
import '../screens/ink_select_ibc_shipment_screen.dart';
import '../screens/ink_select_local_order_screen.dart';
import '../theme/app_theme.dart';
import '../utils/ink_expected_deliveries.dart';

/// Ink home: open local POs + import shipments with ETA overdue…+5 SAST days.
class InkExpectedOrdersBanner extends ConsumerWidget {
  const InkExpectedOrdersBanner({super.key});

  static final _etaFmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(inkExpectedDeliveriesProvider);
    if (rows.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final hasOverdue =
        rows.any((r) => r.urgency == InkExpectedUrgency.overdue);
    final accent = hasOverdue ? scheme.error : kInkModule;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: accent.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: accent.withValues(alpha: 0.45), width: 0.8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _onTap(context, rows),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasOverdue
                      ? Icons.warning_amber_rounded
                      : Icons.inventory_2_outlined,
                  color: accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: rows.length == 1
                      ? _SingleBody(row: rows.first, etaFmt: _etaFmt)
                      : _MultiBody(rows: rows, etaFmt: _etaFmt),
                ),
                Icon(Icons.chevron_right, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, List<InkExpectedDelivery> rows) {
    if (rows.length == 1) {
      _openReceive(context, rows.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Expected Orders (due / overdue)',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final r in rows)
                ListTile(
                  leading: Icon(
                    r.isLocal
                        ? Icons.local_shipping_outlined
                        : Icons.propane_tank_outlined,
                  ),
                  title: Text(r.headline),
                  subtitle: Text(
                    '${r.refLabel} · ETA ${_etaFmt.format(r.eta.toLocal())} (est.) · '
                    '${expectedUrgencyLabel(r.urgency, inDays: r.inDays)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openReceive(context, r);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openReceive(BuildContext context, InkExpectedDelivery row) {
    final page = row.isLocal
        ? const InkSelectLocalOrderScreen()
        : const InkSelectIbcShipmentScreen();
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _SingleBody extends StatelessWidget {
  const _SingleBody({required this.row, required this.etaFmt});

  final InkExpectedDelivery row;
  final DateFormat etaFmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgency =
        expectedUrgencyLabel(row.urgency, inDays: row.inDays);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expected Orders — $urgency',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          row.headline,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'ETA ${etaFmt.format(row.eta.toLocal())} (est.)',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _MultiBody extends StatelessWidget {
  const _MultiBody({required this.rows, required this.etaFmt});

  final List<InkExpectedDelivery> rows;
  final DateFormat etaFmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = rows.length;
    final preview = rows.take(3).toList();
    final more = n - preview.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          n == 1
              ? 'Expected Orders (due / overdue)'
              : '$n Expected Orders (due / overdue)',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (final r in preview) ...[
          Text(
            '· ${expectedUrgencyLabel(r.urgency, inDays: r.inDays)} — ${r.headline}',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '  ETA ${etaFmt.format(r.eta.toLocal())} (est.)',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '· +$more more',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}
