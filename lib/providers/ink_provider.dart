import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_conversion_factor.dart';
import '../models/ink_count_event.dart';
import '../models/ink_ibc.dart';
import '../models/ink_meter_point.dart';
import '../models/ink_production_run.dart';
import '../models/ink_recipe.dart';
import '../models/ink_settings.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_supplier.dart';
import '../models/ink_transaction.dart';
import '../services/ink_service.dart';

final inkServiceProvider = Provider<InkService>((ref) => InkService());

/// Module settings (ink_enabled + closed periods). Loaded once per session and
/// used for home-screen gating, mirroring fleetSettingsProvider.
final inkSettingsProvider = StreamProvider<InkSettings>(
  (ref) => ref.watch(inkServiceProvider).watchSettings(),
);

/// All active stock items with their cached balance/WAC.
final inkStockItemsProvider = StreamProvider<List<InkStockItem>>(
  (ref) => ref.watch(inkServiceProvider).watchStockItems(),
);

/// One stock item's ledger, oldest-effective first.
final inkItemLedgerProvider =
    StreamProvider.family<List<InkTransaction>, String>(
  (ref, itemCode) => ref.watch(inkServiceProvider).watchItemLedger(itemCode),
);

/// Manager "pending costs" queue.
final inkPendingCostsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchPendingCosts(),
);

/// Every transaction (month-end report).
final inkAllTransactionsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchAllTransactions(),
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

/// Production run history (newest first).
final inkProductionRunsProvider = StreamProvider<List<InkProductionRun>>(
  (ref) => ref.watch(inkServiceProvider).watchProductionRuns(),
);

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

/// All meter-point readings (for month-end totals).
final inkMeterPointReadingsProvider = StreamProvider<
    List<({String pointId, double consumption, DateTime readingDate})>>(
  (ref) => ref.watch(inkServiceProvider).watchMeterPointReadings(),
);

/// True if the daily ink meter reading has already been entered today.
final inkTodayInkMeterDoneProvider = StreamProvider<bool>(
  (ref) => ref.watch(inkServiceProvider).watchTodayInkMeterStatus(),
);

/// True if the daily toloul meter reading has already been entered today.
final inkTodayToloulMeterDoneProvider = StreamProvider<bool>(
  (ref) => ref.watch(inkServiceProvider).watchTodayToloulMeterStatus(),
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
