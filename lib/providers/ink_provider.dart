import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_conversion_factor.dart';
import '../models/ink_daily_readings_status.dart';
import '../models/ink_count_event.dart';
import '../models/ink_ibc.dart';
import '../models/ink_meter_point.dart';
import '../models/ink_production_run.dart';
import '../models/ink_purchase_order.dart';
import '../models/ink_recipe.dart';
import '../models/ink_settings.dart';
import '../models/ink_shipment.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_supplier.dart';
import '../models/ink_transaction.dart';
import '../services/ink_service.dart';
import '../utils/ink_ibc_period.dart';
import '../utils/ink_period.dart';

final inkServiceProvider = Provider<InkService>((ref) => InkService());

/// Current open count-to-count window (after latest month-end count, through now).
final inkOpenPeriodRangeProvider = Provider<InkOpenPeriodRange>((ref) {
  final events = ref.watch(inkCountEventsProvider).valueOrNull ?? [];
  return inkOpenPeriodRange(events);
});

/// Module settings (ink_enabled + closed periods). Loaded once per session and
/// used for home-screen gating, mirroring fleetSettingsProvider.
final inkSettingsProvider = StreamProvider<InkSettings>(
  (ref) => ref.watch(inkServiceProvider).watchSettings(),
);

/// All active stock items with their cached balance/WAC.
final inkStockItemsProvider = StreamProvider<List<InkStockItem>>(
  (ref) => ref.watch(inkServiceProvider).watchStockItems(),
);

/// One stock item's ledger, oldest-effective first (manager / Pulse only).
final inkItemLedgerProvider =
    StreamProvider.family<List<InkTransaction>, String>(
  (ref, itemCode) => ref.watch(inkServiceProvider).watchItemLedger(itemCode),
);

/// Operator stock detail — last 20 qty movements only.
final inkItemLedgerRecentProvider =
    StreamProvider.family<List<InkTransaction>, String>(
  (ref, itemCode) =>
      ref.watch(inkServiceProvider).watchItemLedgerRecent(itemCode),
);

/// Manager "pending costs" queue.
final inkPendingCostsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchPendingCosts(),
);

/// Every transaction in the current month (month-end report, legacy/no-snapshot
/// fallback path).
final inkAllTransactionsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchAllTransactions(),
);

/// Transactions on/after a given date — the month-end report watches this keyed
/// by the opening count date when that count carries a WAC/value snapshot, so it
/// replays from the last count instead of from genesis.
final inkTransactionsSinceProvider =
    StreamProvider.family<List<InkTransaction>, DateTime>(
  (ref, from) => ref.watch(inkServiceProvider).watchTransactionsSince(from),
);

/// Manager review queue (flagged movements).
final inkFlaggedProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchFlagged(),
);

/// Active suppliers (for the receive picker).
final inkActiveSuppliersProvider = StreamProvider<List<InkSupplier>>(
  (ref) => ref.watch(inkServiceProvider).watchSuppliers(activeOnly: true),
);

/// All suppliers incl. inactive (for the manager management screen).
final inkAllSuppliersProvider = StreamProvider<List<InkSupplier>>(
  (ref) => ref.watch(inkServiceProvider).watchSuppliers(activeOnly: false),
);

/// Conversion factors (litres→kg) keyed by item code.
final inkConversionFactorsProvider =
    StreamProvider<Map<String, InkConversionFactor>>(
  (ref) => ref.watch(inkServiceProvider).watchConversionFactors(),
);

/// Latest cumulative meter reading per item code.
final inkLatestMeterReadingsProvider = StreamProvider<Map<String, double>>(
  (ref) => ref.watch(inkServiceProvider).watchLatestMeterReadings(),
);

/// Recent meter readings per item (newest first) for the grid view.
final inkRecentMeterReadingsProvider = StreamProvider<
    Map<String, List<({DateTime at, double reading})>>>(
  (ref) => ref.watch(inkServiceProvider).watchRecentMeterReadings(),
);

/// Active recipes (for the production picker).
final inkRecipesProvider = StreamProvider<List<InkRecipe>>(
  (ref) => ref.watch(inkServiceProvider).watchRecipes(activeOnly: true),
);

/// All recipes incl. inactive (for the manager management screen).
final inkAllRecipesProvider = StreamProvider<List<InkRecipe>>(
  (ref) => ref.watch(inkServiceProvider).watchRecipes(activeOnly: false),
);

/// IBCs still in 'received' state (awaiting transfer to a tank).
final inkReceivedIbcsProvider = StreamProvider<List<InkIbc>>(
  (ref) => ref.watch(inkServiceProvider).watchIbcs(status: InkIbcStatus.received),
);

/// All IBCs across all statuses (register view).
final inkAllIbcsProvider = StreamProvider<List<InkIbc>>(
  (ref) => ref.watch(inkServiceProvider).watchIbcs(),
);

/// IBCs consumed (transferred) in the current open count period, newest first.
final inkIbcsConsumedThisPeriodProvider = Provider<List<InkIbc>>((ref) {
  final all = ref.watch(inkAllIbcsProvider).valueOrNull ?? [];
  final range = ref.watch(inkOpenPeriodRangeProvider);
  final consumed = all
      .where((i) => isIbcConsumedInOpenPeriod(i, range))
      .toList()
    ..sort((a, b) {
      final ad = a.transferredDate ?? a.receivedDate;
      final bd = b.transferredDate ?? b.receivedDate;
      return bd.compareTo(ad);
    });
  return consumed;
});

/// Per-colour count of IBCs consumed this period (for Consume IBC tab badges).
final inkIbcsConsumedCountByColourProvider =
    Provider<Map<String, int>>((ref) {
  final all = ref.watch(inkAllIbcsProvider).valueOrNull ?? [];
  final range = ref.watch(inkOpenPeriodRangeProvider);
  return ibcConsumedCountByColour(all, range);
});

/// Open IBC shipments (awaiting_receipt / receiving) to receive against.
final inkOpenShipmentsProvider = StreamProvider<List<InkShipment>>(
  (ref) => ref.watch(inkServiceProvider).watchOpenIbcShipments(),
);

/// Open pallet shipments (raw materials) to receive against.
final inkOpenPalletShipmentsProvider = StreamProvider<List<InkShipment>>(
  (ref) => ref.watch(inkServiceProvider).watchOpenPalletShipments(),
);

/// Sent / partially fulfilled purchase orders (local-loop receipt linking).
final inkOpenPurchaseOrdersProvider = StreamProvider<List<InkPurchaseOrder>>(
  (ref) => ref.watch(inkServiceProvider).watchOpenPurchaseOrders(),
);

/// Production run history (newest first).
final inkProductionRunsProvider = StreamProvider<List<InkProductionRun>>(
  (ref) => ref.watch(inkServiceProvider).watchProductionRuns(),
);

/// Production runs in the current open count period only (operator read-back).
final inkProductionRunsCurrentPeriodProvider =
    Provider<AsyncValue<List<InkProductionRun>>>((ref) {
  final runsAsync = ref.watch(inkProductionRunsProvider);
  final range = ref.watch(inkOpenPeriodRangeProvider);
  return runsAsync.when(
    data: (runs) => AsyncData(
      runs
          .where((r) => isWithinInkOpenPeriod(r.effectiveAt, range))
          .toList(),
    ),
    loading: () => const AsyncLoading(),
    error: (e, st) => AsyncError(e, st),
  );
});

/// Toloul recovery transactions (newest first, non-voided) — high cap so
/// current-period filtering does not drop in-period rows.
final inkRecentRecoveriesProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchRecentRecoveries(limit: 200),
);

/// Recoveries in the current open count period only (operator read-back).
final inkRecentRecoveriesCurrentPeriodProvider =
    Provider<AsyncValue<List<InkTransaction>>>((ref) {
  final recoveriesAsync = ref.watch(inkRecentRecoveriesProvider);
  final range = ref.watch(inkOpenPeriodRangeProvider);
  return recoveriesAsync.when(
    data: (txns) => AsyncData(
      txns
          .where((t) => isWithinInkOpenPeriod(t.effectiveAt, range))
          .toList(),
    ),
    loading: () => const AsyncLoading(),
    error: (e, st) => AsyncError(e, st),
  );
});

/// Active toloul meter points (for the reading screen).
final inkActiveMeterPointsProvider = StreamProvider<List<InkMeterPoint>>(
  (ref) => ref.watch(inkServiceProvider).watchMeterPoints(activeOnly: true),
);

/// All meter points incl. inactive (manager management).
final inkAllMeterPointsProvider = StreamProvider<List<InkMeterPoint>>(
  (ref) => ref.watch(inkServiceProvider).watchMeterPoints(activeOnly: false),
);

/// Latest cumulative reading per meter point.
final inkLatestMeterPointReadingsProvider =
    StreamProvider<Map<String, double>>(
  (ref) => ref.watch(inkServiceProvider).watchLatestMeterPointReadings(),
);

/// Recent readings per meter point (newest first) for the entry grid.
final inkRecentMeterPointReadingsProvider = StreamProvider<
    Map<String, List<({DateTime at, double reading})>>>(
  (ref) => ref.watch(inkServiceProvider).watchRecentMeterPointReadings(),
);

/// All meter-point readings (for month-end totals).
final inkMeterPointReadingsProvider = StreamProvider<
    List<({String pointId, double consumption, DateTime readingDate})>>(
  (ref) => ref.watch(inkServiceProvider).watchMeterPointReadings(),
);

/// Combined ink + toloul daily-readings completion for hub / home banners.
final inkDailyReadingsStatusProvider = StreamProvider<InkDailyReadingsStatus>(
  (ref) {
    final allItems = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final factorsMap =
        ref.watch(inkConversionFactorsProvider).valueOrNull ?? {};
    final requiredInk = allItems
        .where((i) =>
            i.metered &&
            factorsMap[i.itemCode]?.active == true &&
            (factorsMap[i.itemCode]?.kgPerLitre ?? 0) > 0)
        .map((i) => i.itemCode)
        .toSet();
    final toloulPoints =
        ref.watch(inkActiveMeterPointsProvider).valueOrNull ?? [];
    final requiredToloul = {
      for (final p in toloulPoints)
        if (p.id != null) p.id!,
    };
    return ref.watch(inkServiceProvider).watchDailyReadingsStatus(
          requiredInkCodes: requiredInk,
          requiredToloulPointIds: requiredToloul,
        );
  },
);

/// Recent ink meter-reading sessions (grouped by session_id) for the void list.
final inkRecentMeterSessionsProvider = StreamProvider<List<InkMeterSession>>(
  (ref) => ref.watch(inkServiceProvider).watchRecentMeterSessions(),
);

/// All month-end count sessions, newest first.
final inkCountEventsProvider = StreamProvider<List<InkCountEvent>>(
  (ref) => ref.watch(inkServiceProvider).watchCountEvents(),
);

/// Count-event timestamps sorted ascending — used by the month-end report to
/// populate the period selector. Derived from inkCountEventsProvider so it
/// reflects every session, including zero-variance counts that produce no
/// adjustment transactions.
final inkMonthEndCountDatesProvider = Provider<List<DateTime>>((ref) {
  final events = ref.watch(inkCountEventsProvider).valueOrNull ?? [];
  final dates = events.map((e) => e.countDate).toList()..sort();
  return dates;
});
