import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/ink_txn_type.dart';
import 'package:ctp_job_cards/services/ink_ledger.dart';

/// Validates the Ink Factory costing brain (`ink_ledger.dart`) against the
/// LOCKED WAC rules. These use controlled synthetic numbers so each rule is
/// proven in isolation. The full month-end golden test (reproducing the
/// operator's April spreadsheet to the cent) is added once the source
/// spreadsheet is provided as data.
void main() {
  DateTime at(int day) => DateTime(2026, 4, day);

  LedgerEntry entry(
    InkTxnType type,
    int day, {
    double qty = 0,
    double? cost,
    double? newWac,
    bool costPending = false,
  }) =>
      LedgerEntry(
        type: type,
        effectiveAt: at(day),
        quantityDelta: qty,
        totalCost: cost,
        newWac: newWac,
        costPending: costPending,
      );

  group('purchase (WAC-affecting addition)', () {
    test('into empty stock → unit cost becomes WAC', () {
      final r = replayLedger(entries: [
        entry(InkTxnType.purchase, 1, qty: 100, cost: 5750), // R57.50/kg
      ]);
      expect(r.balance, 100);
      expect(r.wac, closeTo(57.5, 1e-9));
      expect(r.value, closeTo(5750, 1e-6));
    });

    test('into existing stock → blended WAC', () {
      // Open 100 @ R10 = R1000; receive 100 @ R20 = R2000 → 200 @ R15.
      final r = replayLedger(
        openingBalance: 100,
        openingWac: 10,
        entries: [entry(InkTxnType.purchase, 1, qty: 100, cost: 2000)],
      );
      expect(r.balance, 200);
      expect(r.wac, closeTo(15, 1e-9));
    });
  });

  group('deferred cost', () {
    test('pending purchase adds qty at current WAC, no WAC change', () {
      final r = replayLedger(
        openingBalance: 100,
        openingWac: 10,
        entries: [entry(InkTxnType.purchase, 1, qty: 100, costPending: true)],
      );
      expect(r.balance, 200);
      expect(r.wac, closeTo(10, 1e-9)); // unchanged while cost pending
    });

    test('re-replay after cost entered recomputes WAC correctly', () {
      // Same purchase, now costed at R2000 → must blend to R15 (no double count).
      final r = replayLedger(
        openingBalance: 100,
        openingWac: 10,
        entries: [entry(InkTxnType.purchase, 1, qty: 100, cost: 2000)],
      );
      expect(r.wac, closeTo(15, 1e-9));
    });
  });

  group('manufacture (WAC-affecting addition)', () {
    test('blends input cost into existing stock', () {
      // Open 8000 @ R34 = R272,000; make 2000 @ input cost R72,000.
      // WAC = (272000 + 72000)/10000 = 34.4.
      final r = replayLedger(
        openingBalance: 8000,
        openingWac: 34,
        entries: [entry(InkTxnType.manufacture, 2, qty: 2000, cost: 72000)],
      );
      expect(r.balance, 10000);
      expect(r.wac, closeTo(34.4, 1e-9));
    });
  });

  group('opening', () {
    test('establishes starting balance and WAC from the seeded value', () {
      final r = replayLedger(entries: [
        entry(InkTxnType.opening, 1, qty: 8104.1, cost: 277514.11),
      ]);
      expect(r.balance, closeTo(8104.1, 1e-6));
      expect(r.wac, closeTo(277514.11 / 8104.1, 1e-6)); // ≈ 34.2437
    });
  });

  group('WAC-neutral movements', () {
    test('consumption reduces balance, WAC unchanged', () {
      final r = replayLedger(
        openingBalance: 200,
        openingWac: 15,
        entries: [entry(InkTxnType.consumptionMeter, 3, qty: -50)],
      );
      expect(r.balance, 150);
      expect(r.wac, closeTo(15, 1e-9));
    });

    test('recovery adds balance at current WAC, WAC unchanged', () {
      final r = replayLedger(
        openingBalance: 30000,
        openingWac: 16.4212,
        entries: [entry(InkTxnType.recovery, 4, qty: 21000)],
      );
      expect(r.balance, 51000);
      expect(r.wac, closeTo(16.4212, 1e-9)); // recovery never moves WAC
    });

    test('adjustment (+/-) moves balance at current WAC, WAC unchanged', () {
      final up = replayLedger(
        openingBalance: 100,
        openingWac: 76.9050,
        entries: [entry(InkTxnType.adjustment, 5, qty: 1239.97)],
      );
      expect(up.balance, closeTo(1339.97, 1e-9));
      expect(up.wac, closeTo(76.9050, 1e-9));

      final down = replayLedger(
        openingBalance: 380,
        openingWac: 124.1936,
        entries: [entry(InkTxnType.adjustment, 5, qty: -1)],
      );
      expect(down.balance, closeTo(379, 1e-9));
      expect(down.wac, closeTo(124.1936, 1e-9));
    });
  });

  group('revaluation', () {
    test('sets WAC, balance unchanged', () {
      final r = replayLedger(
        openingBalance: 500,
        openingWac: 10,
        entries: [entry(InkTxnType.revaluation, 6, newWac: 12.5)],
      );
      expect(r.balance, 500);
      expect(r.wac, closeTo(12.5, 1e-9));
    });
  });

  group('transfer', () {
    test('is quantity-neutral for the stock item', () {
      final r = replayLedger(
        openingBalance: 1000,
        openingWac: 50,
        entries: [entry(InkTxnType.transfer, 7, qty: 0)],
      );
      expect(r.balance, 1000);
      expect(r.wac, closeTo(50, 1e-9));
    });
  });

  group('negative balance (accept-and-flag)', () {
    test('consumption beyond balance is accepted and flagged', () {
      final r = replayLedger(
        openingBalance: 30,
        openingWac: 5,
        entries: [entry(InkTxnType.consumptionMeter, 8, qty: -50)],
      );
      expect(r.balance, -20); // not blocked
      expect(r.hasNegativeStep, isTrue);
    });
  });

  group('backdating / out-of-order replay', () {
    test('entries sort by effectiveAt regardless of input order', () {
      // Provide day-3 consumption BEFORE day-1 purchase; engine must order them.
      final outOfOrder = replayLedger(
        openingBalance: 0,
        openingWac: 0,
        entries: [
          entry(InkTxnType.consumptionMeter, 3, qty: -40),
          entry(InkTxnType.purchase, 1, qty: 100, cost: 1000), // R10/kg
        ],
      );
      // Correct order: +100@R10 then -40 → 60 @ R10.
      expect(outOfOrder.balance, 60);
      expect(outOfOrder.wac, closeTo(10, 1e-9));
    });

    test('a backdated purchase changes downstream WAC after replay', () {
      // Baseline: open 100@R10, purchase day-5 100@R20 → 200@R15.
      final baseline = replayLedger(
        openingBalance: 100,
        openingWac: 10,
        entries: [entry(InkTxnType.purchase, 5, qty: 100, cost: 2000)],
      );
      expect(baseline.wac, closeTo(15, 1e-9));

      // Insert a backdated day-3 purchase 100@R40 BEFORE the day-5 one.
      // Day3: (100·10 + 4000)/200 = 25; Day5: (200·25 + 2000)/300 = 23.333.
      final withBackdate = replayLedger(
        openingBalance: 100,
        openingWac: 10,
        entries: [
          entry(InkTxnType.purchase, 5, qty: 100, cost: 2000),
          entry(InkTxnType.purchase, 3, qty: 100, cost: 4000),
        ],
      );
      expect(withBackdate.balance, 300);
      expect(withBackdate.wac, closeTo(23.3333333, 1e-6));
    });
  });

  group('corrections (voided)', () {
    test('a voided entry is excluded from replay', () {
      final r = replayLedger(
        openingBalance: 100,
        openingWac: 10,
        entries: [
          entry(InkTxnType.consumptionMeter, 2, qty: -50),
          // An erroneous -200 that was corrected → voided, must not apply.
          LedgerEntry(
              type: InkTxnType.consumptionMeter,
              effectiveAt: at(1),
              quantityDelta: -200,
              voided: true),
        ],
      );
      expect(r.balance, 50); // only the -50 applies
      expect(r.wac, closeTo(10, 1e-9));
    });
  });

  group('enum contract', () {
    test('every type round-trips through its Firestore value', () {
      for (final t in InkTxnType.values) {
        expect(InkTxnType.fromValue(t.value), t);
      }
    });

    test('report-column mapping is stable', () {
      expect(InkTxnType.purchase.reportColumn,
          InkReportColumn.purchaseManufacture);
      expect(InkTxnType.manufacture.reportColumn,
          InkReportColumn.purchaseManufacture);
      expect(
          InkTxnType.recovery.reportColumn, InkReportColumn.recoveries);
      expect(InkTxnType.adjustment.reportColumn, InkReportColumn.adjustments);
      expect(
          InkTxnType.revaluation.reportColumn, InkReportColumn.revaluations);
      expect(InkTxnType.transfer.reportColumn, InkReportColumn.none);
      expect(InkTxnType.consumptionMeter.reportColumn,
          InkReportColumn.consumption);
    });
  });
}
