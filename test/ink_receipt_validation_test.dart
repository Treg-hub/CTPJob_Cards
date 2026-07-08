import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/ink_ibc.dart';
import 'package:ctp_job_cards/models/ink_shipment.dart';
import 'package:ctp_job_cards/utils/ink_receipt_validation.dart';

InkShipment _shipment() => const InkShipment(
      id: '51993-K',
      orderNumber: '51993',
      containerLetter: 'K',
      packagingMode: 'ibc',
      status: InkShipmentStatus.awaitingReceipt,
      lines: [
        InkShipmentLine(itemCode: 'black', expectedKg: 2964),
        InkShipmentLine(itemCode: 'yellow', expectedKg: 7663),
      ],
      expectedUnits: [
        // ibcNumber = last 8 of the SSCC
        InkExpectedUnit(sscc: '340456470055101373', itemCode: 'black', netKg: 1002), // 55101373
        InkExpectedUnit(sscc: '340456470055101458', itemCode: 'yellow', netKg: 956), // 55101458
      ],
    );

void main() {
  test('expected unit derives the 8-digit IBC number from the SSCC', () {
    expect(_shipment().expectedUnits.first.ibcNumber, '55101373');
  });

  test('valid rows on the packing list produce no errors', () {
    final errors = validateIbcRowsAgainstShipment(
      shipment: _shipment(),
      rows: const [
        IbcReceiptRow(ibcNumber: '55101373', itemCode: 'black'),
        IbcReceiptRow(ibcNumber: '55101458', itemCode: 'yellow'),
      ],
    );
    expect(errors, isEmpty);
  });

  test('an IBC not on the packing list is rejected', () {
    final errors = validateIbcRowsAgainstShipment(
      shipment: _shipment(),
      rows: const [IbcReceiptRow(ibcNumber: '99999999', itemCode: 'black')],
    );
    expect(errors, hasLength(1));
    expect(errors.first.rowIndex, 0);
    expect(errors.first.message, contains('not on shipment'));
  });

  test('a duplicate IBC scan is rejected', () {
    final errors = validateIbcRowsAgainstShipment(
      shipment: _shipment(),
      rows: const [
        IbcReceiptRow(ibcNumber: '55101373', itemCode: 'black'),
        IbcReceiptRow(ibcNumber: '55101373', itemCode: 'black'),
      ],
    );
    expect(errors, hasLength(1));
    expect(errors.first.message, contains('more than once'));
  });

  test('a wrong colour for a known IBC is rejected', () {
    final errors = validateIbcRowsAgainstShipment(
      shipment: _shipment(),
      rows: const [IbcReceiptRow(ibcNumber: '55101373', itemCode: 'yellow')],
    );
    expect(errors, hasLength(1));
    expect(errors.first.message, contains('is black, not yellow'));
  });

  test('blank rows are skipped', () {
    final errors = validateIbcRowsAgainstShipment(
      shipment: _shipment(),
      rows: const [
        IbcReceiptRow(ibcNumber: '   '),
        IbcReceiptRow(ibcNumber: '55101458', itemCode: 'yellow'),
      ],
    );
    expect(errors, isEmpty);
  });

  test('register conflict on a different shipment blocks receipt', () {
    final conflicts = findIbcRegisterConflicts(
      rows: const [IbcReceiptRow(ibcNumber: '54975531', itemCode: 'yellow')],
      registered: {
        '54975531': InkIbc(
          ibcNumber: '54975531',
          itemCode: 'yellow',
          kg: 954,
          receivedDate: DateTime(2026, 6, 1),
          shipmentId: '51993-J',
        ),
      },
      shipmentId: '51993-K',
    );
    expect(conflicts, hasLength(1));
    expect(conflicts.first.sameShipment, isFalse);
    expect(
      describeIbcRegisterConflict(conflicts.first),
      contains('54975531'),
    );
  });

  test('register conflict on the same shipment is treated as idempotent skip', () {
    final conflicts = findIbcRegisterConflicts(
      rows: const [IbcReceiptRow(ibcNumber: '54975531', itemCode: 'yellow')],
      registered: {
        '54975531': InkIbc(
          ibcNumber: '54975531',
          itemCode: 'yellow',
          kg: 954,
          receivedDate: DateTime(2026, 7, 1),
          shipmentId: '51993-K',
        ),
      },
      shipmentId: '51993-K',
    );
    expect(conflicts, hasLength(1));
    expect(conflicts.first.sameShipment, isTrue);
  });
}
