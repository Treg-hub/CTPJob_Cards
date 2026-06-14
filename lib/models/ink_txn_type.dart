/// Ink Factory transaction types — the single enum that classifies every
/// stock movement in the append-only ledger (`ink_transactions`).
///
/// PURE DART — no Firestore import — so the ledger engine and tests can use it
/// without pulling in plugins. The Firestore model (`ink_transaction.dart`)
/// re-uses these values.
///
/// Each type maps 1:1 to a column on the month-end roll-forward report
/// (see [InkReportColumn]) and has a defined effect on balance and WAC.
/// The financial behaviour itself lives in `ink_ledger.dart`; this file only
/// declares the type, its Firestore string, and its report column.
///
/// LOCKED RULES (see docs/Ink_Factory_Migration_Plan.md §3.2):
///   • WAC changes ONLY on `purchase` (once costed), `manufacture`, `revaluation`.
///   • `recovery` and `adjustment` move quantity at the CURRENT WAC (no WAC change).
///   • All `consumption*` types are deductions issued at the current WAC.
///   • `transfer` (IBC→tank) is quantity-neutral for the stock item (audit only).
enum InkTxnType {
  /// Inbound receipt of raw material or ink-via-IBC. Additive. WAC-affecting
  /// once a cost is entered (deferred-cost: pending receipts add quantity at the
  /// current WAC until the manager captures the shipment cost, then re-replay).
  purchase('purchase', InkReportColumn.purchaseManufacture),

  /// Production output (CoverWax, Gravure Binder). Additive, WAC-affecting:
  /// WAC = total input cost ÷ quantity produced (blended into existing stock).
  manufacture('manufacture', InkReportColumn.purchaseManufacture),

  /// Genesis opening-balance entry (one per item at go-live). WAC-affecting
  /// addition that establishes the starting balance + WAC from a known
  /// stock-take value. Dated before the first live period so it never shows in
  /// a month's Purchase column — the report derives opening by replay-to-date.
  opening('opening', InkReportColumn.none),

  /// Toloul recovered from the Lurgi distillation. Additive, NOT WAC-affecting —
  /// the recovered quantity is valued at the current WAC.
  recovery('recovery', InkReportColumn.recoveries),

  /// Ink / Gravure Binder consumed, read off a meter (or entered directly when
  /// the meter is unavailable — the "manual reading"). Deductive.
  consumptionMeter('consumption_meter', InkReportColumn.consumption),

  /// Raw material or CoverWax consumed as an input to a production batch. Deductive.
  consumptionProduction('consumption_production', InkReportColumn.consumption),

  /// Toloul used to rinse an emptied IBC after transfer to tank. Deductive.
  consumptionTolulWash('consumption_toloul_wash', InkReportColumn.consumption),

  /// Toloul consumed during production. Deductive.
  consumptionTolulProduction(
      'consumption_toloul_production', InkReportColumn.consumption),

  /// Month-end stock-take correction (±). Moves quantity at the current WAC.
  adjustment('adjustment', InkReportColumn.adjustments),

  /// Value-only revaluation under instruction from accounts (rare). Sets the WAC
  /// directly; quantity is unchanged.
  revaluation('revaluation', InkReportColumn.revaluations),

  /// IBC → tank move. Quantity-neutral for the stock item (the ink was already
  /// counted at receipt); recorded for the IBC audit register only.
  transfer('transfer', InkReportColumn.none),

  /// A correction event linking to the transaction it amends. Applied by editing
  /// the corrected transaction and re-replaying; carries no balance effect itself.
  correction('correction', InkReportColumn.none);

  const InkTxnType(this.value, this.reportColumn);

  /// Firestore string value (snake_case, matches house style).
  final String value;

  /// Which month-end report column this type rolls up into.
  final InkReportColumn reportColumn;

  static InkTxnType fromValue(String? value) => InkTxnType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => InkTxnType.adjustment, // safe default; unknown types from future schema are treated as adjustments
      );

  /// True for types that increase quantity in the normal case.
  bool get isAddition =>
      this == purchase ||
      this == manufacture ||
      this == opening ||
      this == recovery;

  /// True for the four deduction types.
  bool get isConsumption => reportColumn == InkReportColumn.consumption;
}

/// Columns of the month-end stock roll-forward report (mirrors the operator's
/// April spreadsheet). The ledger must reproduce this report exactly.
enum InkReportColumn {
  purchaseManufacture,
  consumption,
  recoveries,
  adjustments,
  revaluations,
  none,
}
