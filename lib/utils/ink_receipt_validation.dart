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
