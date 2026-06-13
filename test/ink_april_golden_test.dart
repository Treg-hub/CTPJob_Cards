import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/ink_txn_type.dart';
import 'package:ctp_job_cards/services/ink_ledger.dart';

/// GOLDEN TEST — the acceptance bar for the costing brain.
///
/// Replays the operator's real April-2026 ledger (a direct export from the
/// legacy MS-Access system, `QRYInventoryReport`) through [replayLedger] and
/// asserts that every stock item's closing Balance and WAC reproduce the
/// month-end summary sheet to the cent.
///
/// Fixture: test/fixtures/ink_inventory_2026_04.csv (202 transactions, 11 items).
/// Regenerate from a new month's export with the same column layout.
void main() {
  // Map the legacy Access transaction-type strings onto the locked enum.
  // For the replay math, all WAC-neutral movements behave identically, so the
  // consumption sub-type does not affect the result — only Manufacture/Purchase
  // are WAC-affecting and carry a cost.
  InkTxnType mapType(String s) {
    switch (s) {
      case 'Manufacture':
        return InkTxnType.manufacture;
      case 'Purchase':
        return InkTxnType.purchase;
      case 'Recovery':
        return InkTxnType.recovery;
      case 'Adjustment':
        return InkTxnType.adjustment;
      case 'Consumption - Toloul Wash':
        return InkTxnType.consumptionTolulWash;
      case 'Consumption':
        return InkTxnType.consumptionMeter;
      default:
        throw StateError('Unmapped transaction type: $s');
    }
  }

  test('April 2026 ledger reproduces the month-end summary for every item', () {
    final file =
        File('test/fixtures/ink_inventory_2026_04.csv');
    expect(file.existsSync(), isTrue,
        reason: 'golden fixture missing: ${file.path}');

    final lines = file.readAsLinesSync();
    final header = lines.first.split(',');
    int idx(String name) => header.indexOf(name);
    final iItemId = idx('ItemID');
    final iItemName = idx('ItemName');
    final iDate = idx('TransactionDate');
    final iType = idx('TransactionType');
    final iQty = idx('SignedQty');
    final iCost = idx('TotalCost');
    final iOpenBal = idx('OpeningBalance');
    final iOpenWac = idx('OpeningWAC');
    final iCloseBal = idx('ClosingBalance');
    final iCloseWac = idx('ClosingWAC');

    // Group rows by item, preserving CSV order (already sorted by item, date, id),
    // so equal-timestamp ties keep their original sequence under the stable sort.
    final entriesByItem = <int, List<LedgerEntry>>{};
    final names = <int, String>{};
    final opening = <int, ({double bal, double wac})>{};
    final expected = <int, ({double bal, double wac})>{};

    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final f = line.split(',');
      final id = int.parse(f[iItemId]);
      names[id] = f[iItemName];
      opening.putIfAbsent(id,
          () => (bal: double.parse(f[iOpenBal]), wac: double.parse(f[iOpenWac])));
      expected[id] =
          (bal: double.parse(f[iCloseBal]), wac: double.parse(f[iCloseWac]));

      final type = mapType(f[iType]);
      final costRaw = f[iCost];
      entriesByItem.putIfAbsent(id, () => []).add(LedgerEntry(
            type: type,
            effectiveAt: DateTime.parse(f[iDate]),
            quantityDelta: double.parse(f[iQty]),
            totalCost: (type == InkTxnType.manufacture ||
                        type == InkTxnType.purchase) &&
                    costRaw.isNotEmpty
                ? double.parse(costRaw)
                : null,
          ));
    }

    expect(entriesByItem.length, 11, reason: 'expected 11 stock items');

    final failures = <String>[];
    for (final id in entriesByItem.keys) {
      final result = replayLedger(
        openingBalance: opening[id]!.bal,
        openingWac: opening[id]!.wac,
        entries: entriesByItem[id]!,
      );
      final exp = expected[id]!;
      final dBal = (result.balance - exp.bal).abs();
      final dWac = (result.wac - exp.wac).abs();
      if (dBal > 0.05 || dWac > 0.01) {
        failures.add(
            '${names[id]}: got ${result.balance.toStringAsFixed(2)}@${result.wac.toStringAsFixed(4)} '
            'expected ${exp.bal.toStringAsFixed(2)}@${exp.wac.toStringAsFixed(4)} '
            '(dBal=${dBal.toStringAsFixed(3)} dWac=${dWac.toStringAsFixed(4)})');
      }
    }

    expect(failures, isEmpty,
        reason: 'ledger did not reproduce the summary:\n${failures.join('\n')}');
  });
}
