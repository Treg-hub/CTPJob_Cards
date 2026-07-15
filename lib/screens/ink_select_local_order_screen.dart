import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_purchase_order.dart';
import '../providers/ink_provider.dart';
import '../utils/screen_insets.dart';
import '../widgets/ink_guide_banner.dart';
import 'ink_receive_raw_material_screen.dart';

/// Lists outstanding local purchase orders (sent / partially fulfilled) so the
/// operator picks one before confirming received quantities — mirrors
/// [InkSelectIbcShipmentScreen] for the import IBC path.
///
/// Also shows fulfilled local POs received in the open count-to-count period
/// (greyed, read-only) so floor staff can confirm what they already took in.
class InkSelectLocalOrderScreen extends ConsumerWidget {
  const InkSelectLocalOrderScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _date = DateFormat('dd MMM yyyy');

  void _openReceive(BuildContext context, {InkPurchaseOrder? order}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InkReceiveRawMaterialScreen(initialPurchaseOrder: order),
      ),
    );
  }

  void _alreadyReceived(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Already received')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(inkOpenLocalPurchaseOrdersProvider);
    final receivedAsync = ref.watch(inkReceivedLocalOrdersThisPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Local')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: InkGuideBanner.receiveLocalList(),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not load orders: $e')),
              data: (orders) {
                final received = receivedAsync.valueOrNull ?? const [];
                final receivedLoading = receivedAsync.isLoading;
                final bothEmpty = orders.isEmpty &&
                    received.isEmpty &&
                    !receivedLoading;

                if (bothEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          'No outstanding local orders',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Orders appear here after a manager marks them sent on '
                          'CTP Pulse (RFO approved → Pastel numbers → mark sent). '
                          'Use receive without order only for ad-hoc stock.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => _openReceive(context),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Receive without order'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    ScreenInsets.scrollBottomFullScreen(context),
                  ),
                  children: [
                    if (orders.isNotEmpty) ...[
                      Text(
                        'Select the order you are receiving',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 8),
                      for (final po in orders)
                        _LocalOrderTile(
                          order: po,
                          qty: _qty,
                          onTap: () => _openReceive(context, order: po),
                        ),
                    ] else ...[
                      Text(
                        'No outstanding local orders',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Orders marked sent on Pulse appear here. Received '
                        'orders for this count period are listed below.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openReceive(context),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Receive without order'),
                    ),
                    if (receivedLoading && received.isEmpty) ...[
                      const SizedBox(height: 24),
                      const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                    if (received.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Received this period',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Already received in the current count period — '
                        'visual reference only.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final po in received)
                        _LocalOrderTile(
                          order: po,
                          qty: _qty,
                          received: true,
                          dateFormat: _date,
                          onTap: () => _alreadyReceived(context),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOrderTile extends StatelessWidget {
  const _LocalOrderTile({
    required this.order,
    required this.qty,
    required this.onTap,
    this.received = false,
    this.dateFormat,
  });

  final InkPurchaseOrder order;
  final NumberFormat qty;
  final VoidCallback onTap;
  final bool received;
  final DateFormat? dateFormat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final open = order.openLines;
    final statusLabel = received
        ? 'Received'
        : order.status == InkPurchaseOrderStatus.partiallyFulfilled
            ? 'Partially received'
            : 'Sent — awaiting receipt';
    final preview = open.take(3).map((e) =>
        '${e.line.displayName}: ${qty.format(e.remaining)} ${e.line.unit}');
    final more =
        open.length > 3 ? ' · +${open.length - 3} more line(s)' : '';
    final receivedAt = order.receivedAtForPeriod;
    final lineSummary = order.lines.isEmpty
        ? null
        : '${order.lines.length} line(s)'
            '${order.lines.take(3).map((l) => ' · ${l.displayName}').join()}'
            '${order.lines.length > 3 ? ' · +${order.lines.length - 3} more' : ''}';

    return Opacity(
      opacity: received ? 0.62 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: received ? scheme.surfaceContainerHighest.withValues(alpha: 0.55) : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: received
                ? scheme.surfaceContainerHighest
                : scheme.primaryContainer,
            child: Icon(
              received ? Icons.check_circle_outline : Icons.local_shipping_outlined,
              color: received ? muted : scheme.onPrimaryContainer,
            ),
          ),
          title: Text('${order.pulseRef} · ${order.supplierName}'),
          subtitle: Text(
            [
              if (order.erpOrderNumber != null &&
                  order.erpOrderNumber!.isNotEmpty)
                'Pastel order ${order.erpOrderNumber}',
              statusLabel,
              if (received && receivedAt != null && dateFormat != null)
                dateFormat!.format(receivedAt),
              if (!received && open.isNotEmpty)
                '${open.length} open line(s) · ${preview.join(' · ')}$more',
              if (received && lineSummary != null) lineSummary,
            ].join('\n'),
          ),
          isThreeLine: true,
          trailing: received
              ? Chip(
                  label: const Text('Received'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: scheme.surfaceContainerHighest,
                  labelStyle: TextStyle(fontSize: 12, color: muted),
                  padding: EdgeInsets.zero,
                )
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
