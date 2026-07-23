import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ink_tips_provider.dart';
import '../theme/app_theme.dart';

/// Dismissible process tip for Ink capture screens (Receive Local, IBC, etc.).
/// Hide once → all ink tips hide; restore from Settings → Preferences.
class InkGuideBanner extends ConsumerWidget {
  const InkGuideBanner({
    super.key,
    required this.text,
    this.icon = Icons.lightbulb_outline,
  });

  /// Home hub — what each capture tile is for.
  const InkGuideBanner.home({super.key})
      : text =
            'Capture only on this phone. Receive Local = outstanding local orders '
            '(qty confirm). Receive Ink (IBC) = import drums against a shipment. '
            'Meter readings daily. Managers order, cost, and month-end on CTP Pulse.',
        icon = Icons.factory_outlined;

  /// Outstanding local PO list.
  const InkGuideBanner.receiveLocalList({super.key})
      : text =
            'Orders appear after a manager marks them sent on Pulse (RFO approved → '
            'Pastel numbers → sent). Tap an order, enter what arrived per line. '
            'After save, finish other floor tasks, then capture the delivery note from '
            'the red Pending delivery note rows. Grey rows are complete. '
            'Use Receive without order only for true ad-hoc stock.',
        icon = Icons.local_shipping_outlined;

  /// Multi-line confirm against a PO.
  const InkGuideBanner.receiveLocalConfirm({super.key})
      : text =
            'Enter quantity received for each open line. Leave blank if not on this '
            'delivery. Over/under remaining is fine — residual stays on the order. '
            'Cost is entered later by a manager on Pulse.',
        icon = Icons.checklist_outlined;

  /// Ad-hoc receive without PO.
  const InkGuideBanner.receiveLocalAdHoc({super.key})
      : text =
            'Ad-hoc receipt is not linked to a Pulse order — inbound will not drop. '
            'Prefer selecting an outstanding order when one exists.',
        icon = Icons.edit_note_outlined;

  /// IBC shipment picker.
  const InkGuideBanner.receiveIbcList({super.key})
      : text =
            'Pick the open shipment you are unloading. Packing-list checks apply. '
            'After the load is saved, finish other floor tasks, then capture the '
            'delivery note from the red Pending delivery note rows. Grey rows are complete. '
            'Receive without shipment only for ad-hoc IBCs (manager still costs later).',
        icon = Icons.propane_tank_outlined;

  /// IBC receive form.
  const InkGuideBanner.receiveIbcForm({super.key})
      : text =
            'Scan or type each IBC. Stock rises as cost-pending purchases per colour. '
            'When linked to a shipment, units must match the packing list.',
        icon = Icons.qr_code_scanner;

  /// Daily meter readings.
  const InkGuideBanner.meterReadings({super.key})
      : text =
            'Record ink meters and toloul points for today. Blank fields are skipped. '
            'Over-max readings can flag for board review. One session per calendar day.',
        icon = Icons.speed_outlined;

  /// Consume / transfer IBC.
  const InkGuideBanner.consumeIbc({super.key})
      : text =
            'Transfer an IBC into use: scan or pick colour, enter wash toloul litres. '
            'If you leave wash blank you must confirm no toloul was used (flagged for review). '
            'Mark damaged only if the drum should not enter waste stock.',
        icon = Icons.swap_horiz;

  /// Production run.
  const InkGuideBanner.production({super.key})
      : text =
            'Log a manufacture run from a recipe — quantities only. Costing and WAC '
            'stay on Pulse. Runs list is limited to the open count period.',
        icon = Icons.science_outlined;

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(inkTipsVisibleProvider);
    if (!visible) return const SizedBox.shrink();

    final accent = kInkModule;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Hide tips (Settings > Preferences to bring back)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              ref.read(inkTipsVisibleProvider.notifier).setVisible(false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Ink tips hidden — turn back on in Settings > Preferences',
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
