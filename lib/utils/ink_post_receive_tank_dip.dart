import 'package:flutter/material.dart';

import '../models/ink_purchase_order.dart';
import '../models/ink_shipment.dart';
import '../models/ink_tank_level.dart';
import '../screens/ink_tank_levels_screen.dart';

/// One tank line to offer after delivery-note capture.
class InkPostReceiveDipLine {
  const InkPostReceiveDipLine({
    required this.itemCode,
    required this.displayName,
    required this.unit,
    this.receivedQty,
  });

  final String itemCode;
  final String displayName;
  final String unit;

  /// Qty from this load when known (kg or L). Null = list item only.
  final double? receivedQty;
}

/// Payload returned from DN capture when a post-receive tank dip is relevant.
class InkPostReceiveDipOffer {
  const InkPostReceiveDipOffer({required this.lines});

  final List<InkPostReceiveDipLine> lines;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  List<String> get itemCodes =>
      [for (final l in lines) l.itemCode];

  Map<String, double> get receivedHints {
    final out = <String, double>{};
    for (final l in lines) {
      final q = l.receivedQty;
      if (q != null && q > 0) out[l.itemCode] = q;
    }
    return out;
  }
}

/// Colour ink in IBCs is not in the factory tank until consume — never
/// prompt a dip for those after IBC receive.
const _kIbcColourTankCodes = {'yellow', 'red', 'blue', 'black'};

/// Whether this item should appear on the post-DN tank-dip prompt.
bool shouldSuggestPostReceiveTankDip(
  String itemCode, {
  String? packagingMode,
}) {
  if (!isInkTankItem(itemCode)) return false;
  if (packagingMode == 'ibc' && _kIbcColourTankCodes.contains(itemCode)) {
    return false;
  }
  return true;
}

InkPostReceiveDipOffer? dipOfferFromShipment(InkShipment shipment) {
  final qtyByCode = <String, double>{};
  for (final u in shipment.receivedUnits) {
    final code = u.itemCode;
    if (!shouldSuggestPostReceiveTankDip(
      code,
      packagingMode: shipment.packagingMode,
    )) {
      continue;
    }
    qtyByCode[code] = (qtyByCode[code] ?? 0) + u.netKg;
  }
  // Pallet / edge: units may be empty but lines name tank products.
  if (qtyByCode.isEmpty) {
    for (final line in shipment.lines) {
      if (!shouldSuggestPostReceiveTankDip(
        line.itemCode,
        packagingMode: shipment.packagingMode,
      )) {
        continue;
      }
      qtyByCode[line.itemCode] = line.expectedKg;
    }
  }
  return _offerFromQtyMap(qtyByCode);
}

InkPostReceiveDipOffer? dipOfferFromLocalOrder(InkPurchaseOrder order) {
  // Fulfilled DN path: use ordered lines (qty = ordered − remaining as approx).
  final qtyByCode = <String, double>{};
  final seen = <String>{};
  for (final line in order.lines) {
    final code = line.itemCode;
    if (code.isEmpty || seen.contains(code)) continue;
    seen.add(code);
    if (!shouldSuggestPostReceiveTankDip(code)) continue;
    final remaining = order.remainingFor(code);
    final received = (line.finalKg - remaining).clamp(0.0, double.infinity);
    qtyByCode[code] = received > 1e-6 ? received : line.finalKg;
  }
  for (final code in order.remainingKgByItem.keys) {
    if (seen.contains(code)) continue;
    if (!shouldSuggestPostReceiveTankDip(code)) continue;
    seen.add(code);
    final rem = order.remainingFor(code);
    // Unknown ordered qty — list item without inventing a received total.
    qtyByCode[code] = rem; // may be 0 on fulfilled; still show the tank
  }
  return _offerFromQtyMap(qtyByCode, allowZeroQty: true);
}

InkPostReceiveDipOffer? _offerFromQtyMap(
  Map<String, double> qtyByCode, {
  bool allowZeroQty = false,
}) {
  if (qtyByCode.isEmpty) return null;
  final lines = <InkPostReceiveDipLine>[];
  for (final code in kInkTankItemCodes) {
    if (!qtyByCode.containsKey(code)) continue;
    final qty = qtyByCode[code]!;
    if (!allowZeroQty && qty <= 1e-6) continue;
    lines.add(InkPostReceiveDipLine(
      itemCode: code,
      displayName: kTankDisplayNames[code] ?? code,
      unit: kTankUnits[code] ?? 'KG',
      receivedQty: qty > 1e-6 ? qty : null,
    ));
  }
  if (lines.isEmpty) return null;
  return InkPostReceiveDipOffer(lines: lines);
}

/// After DN save: offer tank dip when load includes factory-tank materials.
Future<void> presentPostReceiveTankDipPrompt(
  BuildContext context,
  InkPostReceiveDipOffer offer,
) async {
  if (offer.isEmpty) return;
  if (!context.mounted) return;

  final names = offer.lines.map((l) {
    final q = l.receivedQty;
    if (q == null) return l.displayName;
    final qtyStr = q == q.roundToDouble()
        ? q.toStringAsFixed(0)
        : q.toStringAsFixed(1);
    return '${l.displayName} (~$qtyStr ${l.unit} this load)';
  }).join('\n');

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Update factory tank levels?'),
      content: SingleChildScrollView(
        child: Text(
          'Delivery note is saved and stock is on the ledger.\n\n'
          'Purchase does not auto-fill tank %full. If this product was put '
          'into a factory tank, record a physical dip now.\n\n'
          'Tanks on this load:\n$names\n\n'
          'Skip if product is still in drums/yard, or dip later from Tank levels.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Skip for now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Update tanks'),
        ),
      ],
    ),
  );

  if (go != true || !context.mounted) return;

  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => InkTankLevelsScreen(
        focusItemCodes: offer.itemCodes,
        receivedHints: offer.receivedHints,
        postReceiveContext: true,
      ),
    ),
  );
}
