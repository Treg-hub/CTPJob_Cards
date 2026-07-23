import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_purchase_order.dart';
import '../models/ink_shipment.dart';
import '../providers/ink_provider.dart';
import '../screens/ink_capture_delivery_note_screen.dart';

Future<void> openInkDeliveryNoteCapture(
  BuildContext context, {
  InkShipment? shipment,
  InkPurchaseOrder? order,
}) async {
  assert(shipment != null || order != null);
  await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => shipment != null
          ? InkCaptureDeliveryNoteScreen.shipment(shipment: shipment)
          : InkCaptureDeliveryNoteScreen.localOrder(order: order!),
    ),
  );
}

/// Refresh one-shot "received this period" lists after receive or DN attach.
void invalidateInkReceivedPeriodLists(WidgetRef ref) {
  ref.invalidate(inkReceivedLocalOrdersThisPeriodProvider);
  ref.invalidate(inkReceivedIbcShipmentsThisPeriodProvider);
}

/// Soft red fill so pending-DN rows read as "action needed".
Color inkPendingDeliveryNoteFill(ColorScheme scheme) =>
    scheme.error.withValues(alpha: 0.14);

Color inkPendingDeliveryNoteBorder(ColorScheme scheme) =>
    scheme.error.withValues(alpha: 0.45);
