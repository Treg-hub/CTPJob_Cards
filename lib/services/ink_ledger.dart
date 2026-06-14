import '../models/ink_txn_type.dart';

/// The Ink Factory costing "brain": a PURE-DART weighted-average-cost (WAC)
/// ledger replay engine. Given a stock item's opening position and its list of
/// transactions, it replays them in effective-time order and produces the
/// running balance / WAC / value at every step plus the closing position.
///
/// No Firestore, no Flutter — so it is fast to unit-test and is the single
/// source of truth that the server write path and the month-end report both
/// reuse. (Ported and corrected from CTPInk_Factory's `wac_calculator.dart` +
/// `wac_replay.dart`.)
///
/// ## Locked WAC rules (docs/Ink_Factory_Migration_Plan.md §3.2)
///   • `purchase` (once costed) and `manufacture` RECOMPUTE WAC:
///       wacAfter = (balance·wac + costIn) / (balance + qtyIn)
///       — or, when balance ≤ 0, the unit cost (costIn / qtyIn) becomes the WAC.
///   • `revaluation` SETS the WAC directly; quantity unchanged.
///   • `recovery`, `adjustment`, and every `consumption*` move quantity at the
///     CURRENT WAC — WAC is unchanged.
///   • `transfer` is quantity-neutral for the stock item (no-op here).
///   • A `purchase` whose cost has not yet been entered ([LedgerEntry.costPending])
///     adds quantity at the current WAC; when the manager later enters the cost,
///     the entry is re-replayed and WAC recomputes correctly.
///
/// ## Backdating / out-of-order entry
/// Callers pass [LedgerEntry.effectiveAt] (when it actually happened). [replay]
/// sorts by it, so a backdated or late-syncing offline entry slots into its
/// correct chronological position and everything after it is recomputed.
///
/// ## Negative balances
/// Per the accept-and-flag decision, a step that drives the balance below zero
/// is NOT blocked — it is recorded with [LedgerStep.flaggedNegative] = true for
/// manager review.

/// One transaction's inputs to the engine (the financially-relevant subset of
/// the full Firestore record).
class LedgerEntry {
  const LedgerEntry({
    required this.type,
    required this.effectiveAt,
    this.quantityDelta = 0,
    this.totalCost,
    this.newWac,
    this.costPending = false,
    this.voided = false,
  });

  final InkTxnType type;

  /// When the movement actually happened — drives replay ordering.
  final DateTime effectiveAt;

  /// Signed quantity change (deductions negative; transfer/revaluation 0).
  final double quantityDelta;

  /// For `purchase` / `manufacture`: the total value flowing in (e.g. qty ×
  /// price for a purchase, or total input cost for a manufacture). Ignored for
  /// other types.
  final double? totalCost;

  /// For `revaluation`: the WAC to set. Ignored for other types.
  final double? newWac;

  /// For `purchase`: true while the shipment cost has not yet been captured.
  final bool costPending;

  /// Voided by a correction — excluded from the replay (the original row is
  /// preserved for audit but no longer affects balance/WAC).
  final bool voided;
}

/// The computed position around a single replayed step.
class LedgerStep {
  const LedgerStep({
    required this.entry,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.wacBefore,
    required this.wacAfter,
    required this.flaggedNegative,
  });

  final LedgerEntry entry;
  final double balanceBefore;
  final double balanceAfter;
  final double wacBefore;
  final double wacAfter;

  /// True when [balanceAfter] < 0 (accept-and-flag for manager review).
  final bool flaggedNegative;

  /// Stock value after this step (balance × WAC).
  double get valueAfter => balanceAfter * wacAfter;
}

/// Closing position plus the per-step trace.
class LedgerResult {
  const LedgerResult({
    required this.balance,
    required this.wac,
    required this.steps,
  });

  final double balance;
  final double wac;
  final List<LedgerStep> steps;

  /// Closing stock value (balance × WAC).
  double get value => balance * wac;

  /// True if any step in the replay went negative.
  bool get hasNegativeStep => steps.any((s) => s.flaggedNegative);
}

/// Replays [entries] for ONE stock item from the given opening position.
///
/// Entries are sorted by [LedgerEntry.effectiveAt] (stable), so callers may pass
/// them in any order — this is what makes backdating and offline replay work.
LedgerResult replayLedger({
  double openingBalance = 0,
  double openingWac = 0,
  required List<LedgerEntry> entries,
}) {
  final sorted = [...entries]
    ..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));

  var balance = openingBalance;
  var wac = openingWac;
  final steps = <LedgerStep>[];

  for (final e in sorted) {
    if (e.voided) continue; // excluded by a correction
    final balBefore = balance;
    final wacBefore = wac;

    switch (e.type) {
      case InkTxnType.manufacture:
      case InkTxnType.opening:
        // WAC-affecting addition (opening establishes starting balance + WAC).
        (balance, wac) = _applyWacAffectingAddition(e, balBefore, wacBefore);
        break;

      case InkTxnType.purchase:
        if (e.costPending) {
          // Provisional: quantity in at the current WAC; WAC recomputes later
          // when the cost is entered and this entry is re-replayed.
          balance = balBefore + e.quantityDelta;
        } else {
          (balance, wac) = _applyWacAffectingAddition(e, balBefore, wacBefore);
        }
        break;

      case InkTxnType.revaluation:
        // Value-only: set WAC, quantity unchanged.
        if (e.newWac != null) wac = e.newWac!;
        break;

      case InkTxnType.recovery:
      case InkTxnType.adjustment:
      case InkTxnType.consumptionMeter:
      case InkTxnType.consumptionProduction:
      case InkTxnType.consumptionTolulWash:
      case InkTxnType.consumptionTolulProduction:
        // Quantity moves at the current WAC; WAC unchanged.
        balance = balBefore + e.quantityDelta;
        break;

      case InkTxnType.valueAdjustment:
        // Cost-only adjustment (rand amount in totalCost, can be negative).
        // WAC = (balance × currentWac + amount) / balance; quantity unchanged.
        if (balBefore > 0 && e.totalCost != null) {
          wac = (balBefore * wacBefore + e.totalCost!) / balBefore;
        }
        break;

      case InkTxnType.transfer:
      case InkTxnType.correction:
        // Quantity-neutral for this stock item.
        break;
    }

    steps.add(LedgerStep(
      entry: e,
      balanceBefore: balBefore,
      balanceAfter: balance,
      wacBefore: wacBefore,
      wacAfter: wac,
      flaggedNegative: balance < 0,
    ));
  }

  return LedgerResult(balance: balance, wac: wac, steps: steps);
}

/// Returns the (balance, wac) after applying the WAC-recomputing addition
/// formula for a `purchase` (costed) or `manufacture` entry.
(double balance, double wac) _applyWacAffectingAddition(
  LedgerEntry e,
  double balanceBefore,
  double wacBefore,
) {
  final qty = e.quantityDelta;
  final cost = e.totalCost ?? 0;
  final newBalance = balanceBefore + qty;
  final double newWac;
  if (balanceBefore <= 0) {
    // No existing inventory to average against — unit cost becomes the WAC.
    newWac = qty > 0 ? cost / qty : wacBefore;
  } else {
    newWac =
        newBalance > 0 ? (balanceBefore * wacBefore + cost) / newBalance : 0;
  }
  return (newBalance, newWac);
}
