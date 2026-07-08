import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../models/ink_shipment.dart';

/// A single validation problem for a receive row. [rowIndex] is 0-based;
/// -1 means a shipment-level (non-row) problem.
class IbcReceiptError {
  const IbcReceiptError(this.rowIndex, this.message);
  final int rowIndex;
  final String message;
}

/// A row the operator has entered/scanned (only the fields validation needs).
class IbcReceiptRow {
  const IbcReceiptRow({required this.ibcNumber, this.itemCode});
  final String ibcNumber;
  final String? itemCode;
}

/// Validates scanned/typed IBC rows against a shipment's expected packing-list
/// units. Pure (no Flutter/Firestore) so it is unit-testable. Returns an empty
/// list when every non-blank row is valid.
///
/// Rules (only applied when receiving AGAINST a shipment):
///  - the IBC number must appear on the shipment's packing list,
///  - it must not be scanned more than once,
///  - its colour, if chosen, must match the packing list.
List<IbcReceiptError> validateIbcRowsAgainstShipment({
  required InkShipment shipment,
  required List<IbcReceiptRow> rows,
}) {
  final errors = <IbcReceiptError>[];
  final byNumber = {for (final u in shipment.expectedUnits) u.ibcNumber: u};
  final seen = <String>{};

  for (var i = 0; i < rows.length; i++) {
    final number = rows[i].ibcNumber.trim();
    if (number.isEmpty) continue;

    final unit = byNumber[number];
    if (unit == null) {
      errors.add(IbcReceiptError(
          i, 'IBC $number is not on shipment ${shipment.id}’s packing list.'));
      continue;
    }
    if (!seen.add(number)) {
      errors.add(IbcReceiptError(i, 'IBC $number scanned more than once.'));
      continue;
    }
    final chosen = rows[i].itemCode;
    if (chosen != null && chosen != unit.itemCode) {
      errors.add(IbcReceiptError(
          i, 'IBC $number is ${unit.itemCode}, not $chosen.'));
    }
  }
  return errors;
}

/// A scanned row that already exists in `ink_ibcs`.
class IbcRegisterConflict {
  const IbcRegisterConflict({
    required this.rowIndex,
    required this.ibcNumber,
    required this.existing,
    required this.sameShipment,
  });

  final int rowIndex;
  final String ibcNumber;
  final InkIbc existing;
  final bool sameShipment;
}

/// Finds rows that collide with the IBC audit register.
List<IbcRegisterConflict> findIbcRegisterConflicts({
  required List<IbcReceiptRow> rows,
  required Map<String, InkIbc> registered,
  String? shipmentId,
}) {
  final conflicts = <IbcRegisterConflict>[];
  for (var i = 0; i < rows.length; i++) {
    final number = rows[i].ibcNumber.trim();
    if (number.length != 8) continue;
    final existing = registered[number];
    if (existing == null) continue;
    conflicts.add(IbcRegisterConflict(
      rowIndex: i,
      ibcNumber: number,
      existing: existing,
      sameShipment:
          shipmentId != null && existing.shipmentId == shipmentId,
    ));
  }
  return conflicts;
}

String describeIbcRegisterConflict(IbcRegisterConflict conflict) {
  final df = DateFormat('d MMM yyyy');
  final parts = <String>[
    'IBC ${conflict.ibcNumber} is already registered',
    '(${df.format(conflict.existing.receivedDate)})',
  ];
  if (conflict.existing.shipmentId != null &&
      conflict.existing.shipmentId!.isNotEmpty) {
    parts.add('on shipment ${conflict.existing.shipmentId}');
  } else if (conflict.existing.orderNumber != null &&
      conflict.existing.orderNumber!.isNotEmpty) {
    parts.add('for order ${conflict.existing.orderNumber}');
  }
  return parts.join(' ');
}

/// User-facing message for receive failures (no stack traces).
String formatInkIbcReceiptError(Object error) {
  if (error is FirebaseFunctionsException) {
    final msg = error.message?.trim();
    switch (error.code) {
      case 'already-exists':
        return msg ??
            'One or more IBCs are already registered. Remove them from this receipt.';
      case 'failed-precondition':
        return msg ?? 'This shipment has already been received.';
      case 'not-found':
        return msg ?? 'Shipment not found. Refresh and try again.';
      case 'unauthenticated':
        return 'Sign in again, then retry the receipt.';
      case 'permission-denied':
        return 'You do not have permission to receive ink.';
      default:
        return msg ?? 'Receipt failed (${error.code}). Please try again.';
    }
  }
  return 'Receipt failed. Please try again.';
}
