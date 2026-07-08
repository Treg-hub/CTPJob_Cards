import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_shipment.dart';
import '../providers/ink_provider.dart';
import 'ink_receive_ibc_screen.dart';
import '../utils/screen_insets.dart';

/// Lists outstanding IBC shipments (awaiting receipt in Pulse) so the operator
/// picks one before capturing IBCs against its packing list.
class InkSelectIbcShipmentScreen extends ConsumerWidget {
  const InkSelectIbcShipmentScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');

  void _openReceive(BuildContext context, {InkShipment? shipment}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InkReceiveIbcScreen(initialShipment: shipment),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipmentsAsync = ref.watch(inkOpenShipmentsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Ink (IBC)')),
      body: shipmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load shipments: $e')),
        data: (shipments) {
          if (shipments.isEmpty) {
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

          return ListView(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              ScreenInsets.scrollBottomFullScreen(context),
            ),
            children: [
              Text(
                'Select the shipment you are unloading',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              for (final s in shipments) _ShipmentTile(
                shipment: s,
                qty: _qty,
                onTap: () => _openReceive(context, shipment: s),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openReceive(context),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Receive without shipment'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShipmentTile extends StatelessWidget {
  const _ShipmentTile({
    required this.shipment,
    required this.qty,
    required this.onTap,
  });

  final InkShipment shipment;
  final NumberFormat qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(
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
            '$unitCount IBC${unitCount == 1 ? '' : 's'}$progress'
                '${colours > 0 ? ' · $colours colour${colours == 1 ? '' : 's'}' : ''}'
                '${totalKg > 0 ? ' · ${qty.format(totalKg)} kg' : ''}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}