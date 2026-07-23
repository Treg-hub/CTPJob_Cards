import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_purchase_order.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_delivery_note_flow.dart';
import '../utils/screen_insets.dart';
import '../widgets/ink_guide_banner.dart';
import 'ink_receive_raw_material_screen.dart';

/// Lists outstanding local purchase orders (sent / partially fulfilled) so the
/// operator picks one before confirming received quantities — mirrors
/// [InkSelectIbcShipmentScreen] for the import IBC path.
///
/// After receive: **Pending delivery note** (red) until POD photo; then greyed
/// **Received this period** (complete).
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

  void _alreadyComplete(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Already complete — delivery note on file')),
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
                final pendingDn =
                    received.where((po) => po.needsDeliveryNote).toList();
                final complete = received
                    .where((po) => po.hasDeliveryNote)
                    .toList();
                final receivedLoading = receivedAsync.isLoading;
                final bothEmpty = orders.isEmpty &&
                    pendingDn.isEmpty &&
                    complete.isEmpty &&
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

                return RefreshIndicator(
                  onRefresh: () async {
                    invalidateInkReceivedPeriodLists(ref);
                    await ref.read(
                        inkReceivedLocalOrdersThisPeriodProvider.future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        for (final po in orders)
                          _LocalOrderTile(
                            order: po,
                            qty: _qty,
                            // Partial receive: still open, but DN may be due.
                            pendingDn: po.status ==
                                    InkPurchaseOrderStatus
                                        .partiallyFulfilled &&
                                !po.hasDeliveryNote,
                            onTap: () => _openReceive(context, order: po),
                            onCaptureDn: po.status ==
                                        InkPurchaseOrderStatus
                                            .partiallyFulfilled &&
                                    !po.hasDeliveryNote
                                ? () => openInkDeliveryNoteCapture(
                                      context,
                                      order: po,
                                    ).then((_) {
                                      if (context.mounted) {
                                        invalidateInkReceivedPeriodLists(ref);
                                      }
                                    })
                                : null,
                          ),
                      ] else ...[
                        Text(
                          'No outstanding local orders',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
                      if (receivedLoading &&
                          pendingDn.isEmpty &&
                          complete.isEmpty) ...[
                        const SizedBox(height: 24),
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                      if (pendingDn.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Pending delivery note',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.error),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stock is received — photograph the signed transporter '
                          'note to complete each load.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final po in pendingDn)
                          _LocalOrderTile(
                            order: po,
                            qty: _qty,
                            pendingDn: true,
                            dateFormat: _date,
                            onTap: () => openInkDeliveryNoteCapture(
                              context,
                              order: po,
                            ).then((_) {
                              if (context.mounted) {
                                invalidateInkReceivedPeriodLists(ref);
                              }
                            }),
                          ),
                      ],
                      if (complete.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Received this period',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Complete — delivery note on file.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final po in complete)
                          _LocalOrderTile(
                            order: po,
                            qty: _qty,
                            received: true,
                            dateFormat: _date,
                            onTap: () => _alreadyComplete(context),
                          ),
                      ],
                    ],
                  ),
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
    this.pendingDn = false,
    this.dateFormat,
    this.onCaptureDn,
  });

  final InkPurchaseOrder order;
  final NumberFormat qty;
  final VoidCallback onTap;
  final bool received;
  final bool pendingDn;
  final DateFormat? dateFormat;
  final VoidCallback? onCaptureDn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final open = order.openLines;
    final statusLabel = received
        ? 'Complete'
        : pendingDn && order.status == InkPurchaseOrderStatus.partiallyFulfilled
            ? 'Partially received — delivery note needed'
            : pendingDn
                ? 'Received — delivery note needed'
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

    final Color? cardColor = received
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : pendingDn
            ? inkPendingDeliveryNoteFill(scheme)
            : null;

    return Opacity(
      opacity: received ? 0.62 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: cardColor,
        shape: pendingDn
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: inkPendingDeliveryNoteBorder(scheme),
                  width: 1,
                ),
              )
            : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: received
                ? scheme.surfaceContainerHighest
                : pendingDn
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
            child: Icon(
              received
                  ? Icons.check_circle_outline
                  : pendingDn
                      ? Icons.photo_camera_outlined
                      : Icons.local_shipping_outlined,
              color: received
                  ? muted
                  : pendingDn
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
            ),
          ),
          title: Text('${order.pulseRef} · ${order.supplierName}'),
          subtitle: Text(
            [
              if (order.erpOrderNumber != null &&
                  order.erpOrderNumber!.isNotEmpty)
                'Pastel order ${order.erpOrderNumber}',
              statusLabel,
              if ((received || pendingDn) &&
                  receivedAt != null &&
                  dateFormat != null)
                dateFormat!.format(receivedAt),
              if (!received && !pendingDn && open.isNotEmpty)
                '${open.length} open line(s) · ${preview.join(' · ')}$more',
              if ((received || pendingDn) && lineSummary != null) lineSummary,
              if (pendingDn && open.isNotEmpty)
                '${open.length} open line(s) still on order',
            ].join('\n'),
          ),
          isThreeLine: true,
          trailing: received
              ? Chip(
                  label: const Text('Complete'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: scheme.surfaceContainerHighest,
                  labelStyle: TextStyle(fontSize: 12, color: muted),
                  padding: EdgeInsets.zero,
                )
              : pendingDn
                  ? (onCaptureDn != null
                      ? IconButton(
                          tooltip: 'Capture delivery note',
                          onPressed: onCaptureDn,
                          icon: Icon(Icons.photo_camera, color: scheme.error),
                        )
                      : Chip(
                          label: const Text('Action needed'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: scheme.errorContainer,
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: scheme.onErrorContainer,
                          ),
                          padding: EdgeInsets.zero,
                        ))
                  : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
