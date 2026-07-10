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
class InkSelectLocalOrderScreen extends ConsumerWidget {
  const InkSelectLocalOrderScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');

  void _openReceive(BuildContext context, {InkPurchaseOrder? order}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InkReceiveRawMaterialScreen(initialPurchaseOrder: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(inkOpenLocalPurchaseOrdersProvider);
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
                if (orders.isEmpty) {
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
                    Text(
                      'Select the order you are receiving',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openReceive(context),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Receive without order'),
                    ),
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
  });

  final InkPurchaseOrder order;
  final NumberFormat qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = order.openLines;
    final statusLabel = order.status == InkPurchaseOrderStatus.partiallyFulfilled
        ? 'Partially received'
        : 'Sent — awaiting receipt';
    final preview = open.take(3).map((e) =>
        '${e.line.displayName}: ${qty.format(e.remaining)} ${e.line.unit}');
    final more =
        open.length > 3 ? ' · +${open.length - 3} more line(s)' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            Icons.local_shipping_outlined,
            color: scheme.onPrimaryContainer,
          ),
        ),
        title: Text('${order.pulseRef} · ${order.supplierName}'),
        subtitle: Text(
          [
            if (order.erpOrderNumber != null && order.erpOrderNumber!.isNotEmpty)
              'Pastel order ${order.erpOrderNumber}',
            statusLabel,
            if (open.isNotEmpty)
              '${open.length} open line(s) · ${preview.join(' · ')}$more',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
