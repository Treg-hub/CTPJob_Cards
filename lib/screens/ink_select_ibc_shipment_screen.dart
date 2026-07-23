import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_shipment.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_delivery_note_flow.dart';
import 'ink_receive_ibc_screen.dart';
import '../utils/screen_insets.dart';
import '../widgets/ink_guide_banner.dart';

/// Lists outstanding IBC shipments (awaiting receipt in Pulse) so the operator
/// picks one before capturing IBCs against its packing list.
///
/// After receive: **Pending delivery note** (red) until POD photo; then greyed
/// **Received this period** (complete).
class InkSelectIbcShipmentScreen extends ConsumerWidget {
  const InkSelectIbcShipmentScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _date = DateFormat('dd MMM yyyy');

  void _openReceive(BuildContext context, {InkShipment? shipment}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InkReceiveIbcScreen(initialShipment: shipment),
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
    final shipmentsAsync = ref.watch(inkOpenShipmentsProvider);
    final receivedAsync = ref.watch(inkReceivedIbcShipmentsThisPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Ink (IBC)')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: InkGuideBanner.receiveIbcList(),
          ),
          Expanded(
            child: shipmentsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not load shipments: $e')),
              data: (shipments) {
                final received = receivedAsync.valueOrNull ?? const [];
                final pendingDn =
                    received.where((s) => s.needsDeliveryNote).toList();
                final complete =
                    received.where((s) => s.hasDeliveryNote).toList();
                final receivedLoading = receivedAsync.isLoading;
                final bothEmpty = shipments.isEmpty &&
                    pendingDn.isEmpty &&
                    complete.isEmpty &&
                    !receivedLoading;

                if (bothEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          'No outstanding IBC shipments',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Receive without a shipment if stock arrived ad hoc, '
                          'or ask a manager to create the shipment in CTP Pulse.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => _openReceive(context),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Receive without shipment'),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    invalidateInkReceivedPeriodLists(ref);
                    await ref.read(
                        inkReceivedIbcShipmentsThisPeriodProvider.future);
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
                      if (shipments.isNotEmpty) ...[
                        Text(
                          'Select the shipment you are unloading',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        for (final s in shipments)
                          _ShipmentTile(
                            shipment: s,
                            qty: _qty,
                            onTap: () => _openReceive(context, shipment: s),
                          ),
                      ] else ...[
                        Text(
                          'No outstanding IBC shipments',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Shipments awaiting receipt appear here. Received '
                          'shipments for this count period are listed below.',
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
                        label: const Text('Receive without shipment'),
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
                      if (receivedAsync.hasError &&
                          pendingDn.isEmpty &&
                          complete.isEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Could not load received shipments. Pull to refresh or try again.',
                          style: TextStyle(color: scheme.error, fontSize: 13),
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
                          'note to complete each container.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final s in pendingDn)
                          _ShipmentTile(
                            shipment: s,
                            qty: _qty,
                            pendingDn: true,
                            dateFormat: _date,
                            onTap: () => openInkDeliveryNoteCapture(
                              context,
                              shipment: s,
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
                        for (final s in complete)
                          _ShipmentTile(
                            shipment: s,
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

class _ShipmentTile extends StatelessWidget {
  const _ShipmentTile({
    required this.shipment,
    required this.qty,
    required this.onTap,
    this.received = false,
    this.pendingDn = false,
    this.dateFormat,
  });

  final InkShipment shipment;
  final NumberFormat qty;
  final VoidCallback onTap;
  final bool received;
  final bool pendingDn;
  final DateFormat? dateFormat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final unitCount = shipment.expectedUnits.length;
    final receivedCount = shipment.receivedIbcCount;
    final totalKg = shipment.expectedUnits.fold<double>(
      0,
      (sum, u) => sum + u.netKg,
    );
    final colours = shipment.itemCodes.length;
    final progress = unitCount > 0 && receivedCount > 0
        ? ' · $receivedCount / $unitCount received'
        : '';
    final receivedAt = shipment.receivedAtForPeriod;

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
            child: received
                ? Icon(Icons.check_circle_outline, color: muted)
                : pendingDn
                    ? Icon(Icons.photo_camera_outlined,
                        color: scheme.onErrorContainer)
                    : Text(
                        shipment.containerLetter,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
          ),
          title: Text(shipment.id),
          subtitle: Text(
            [
              if (shipment.containerNumber != null)
                'Container ${shipment.containerNumber}',
              'Order ${shipment.orderNumber}',
              if (shipment.cgnaNumber != null) 'CGNA ${shipment.cgnaNumber}',
              if (received) 'Complete',
              if (pendingDn) 'Received — delivery note needed',
              if ((received || pendingDn) &&
                  receivedAt != null &&
                  dateFormat != null)
                dateFormat!.format(receivedAt),
              '$unitCount IBC${unitCount == 1 ? '' : 's'}$progress'
                  '${colours > 0 ? ' · $colours colour${colours == 1 ? '' : 's'}' : ''}'
                  '${totalKg > 0 ? ' · ${qty.format(totalKg)} kg' : ''}',
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
                  ? Chip(
                      label: const Text('Action needed'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: scheme.errorContainer,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: scheme.onErrorContainer,
                      ),
                      padding: EdgeInsets.zero,
                    )
                  : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
