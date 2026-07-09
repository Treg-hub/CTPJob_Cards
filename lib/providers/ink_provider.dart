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

/// Module settings (ink_enabled + closed periods).
final inkSettingsProvider = StreamProvider<InkSettings>(
  (ref) => ref.watch(inkServiceProvider).watchSettings(),
);

/// All active stock items with their cached balance/WAC.
final inkStockItemsProvider = StreamProvider<List<InkStockItem>>(
  (ref) => ref.watch(inkServiceProvider).watchStockItems(),
);

/// Item ledger for the open period only (mobile).
final inkItemLedgerProvider =
    StreamProvider.family<List<InkTransaction>, String>((ref, itemCode) {
  final from = ref.watch(inkOpenPeriodRangeProvider).fromExclusive;
  return ref.watch(inkServiceProvider).watchItemLedger(
        itemCode,
        periodFromExclusive: from,
      );
});

/// Operator stock detail — last 20 qty movements in open period.
final inkItemLedgerRecentProvider =
    StreamProvider.family<List<InkTransaction>, String>((ref, itemCode) {
  final from = ref.watch(inkOpenPeriodRangeProvider).fromExclusive;
  return ref.watch(inkServiceProvider).watchItemLedgerRecent(
        itemCode,
        periodFromExclusive: from,
      );
});

/// Recent ledger lines already period-scoped at query time.
final inkItemLedgerRecentCurrentPeriodProvider =
    Provider.family<AsyncValue<List<InkTransaction>>, String>((ref, itemCode) {
  return ref.watch(inkItemLedgerRecentProvider(itemCode));
});

final inkPendingCostsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchPendingCosts(),
);

final inkAllTransactionsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchAllTransactions(),
);

final inkTransactionsSinceProvider =
    StreamProvider.family<List<InkTransaction>, DateTime>(
  (ref, from) => ref.watch(inkServiceProvider).watchTransactionsSince(from),
);

final inkFlaggedProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchFlagged(),
);

final inkActiveSuppliersProvider = StreamProvider<List<InkSupplier>>(
  (ref) => ref.watch(inkServiceProvider).watchSuppliers(activeOnly: true),
);

final inkAllSuppliersProvider = StreamProvider<List<InkSupplier>>(
  (ref) => ref.watch(inkServiceProvider).watchSuppliers(activeOnly: false),
);

final inkConversionFactorsProvider =
    StreamProvider<Map<String, InkConversionFactor>>(
  (ref) => ref.watch(inkServiceProvider).watchConversionFactors(),
);

final inkLatestMeterReadingsProvider = StreamProvider<Map<String, double>>(
  (ref) => ref.watch(inkServiceProvider).watchLatestMeterReadings(),
);

final inkRecentMeterReadingsProvider = StreamProvider<
    Map<String, List<({DateTime at, double reading})>>>(
  (ref) => ref.watch(inkServiceProvider).watchRecentMeterReadings(),
);

final inkRecipesProvider = StreamProvider<List<InkRecipe>>(
  (ref) => ref.watch(inkServiceProvider).watchRecipes(activeOnly: true),
);

final inkAllRecipesProvider = StreamProvider<List<InkRecipe>>(
  (ref) => ref.watch(inkServiceProvider).watchRecipes(activeOnly: false),
);

final inkReceivedIbcsProvider = StreamProvider<List<InkIbc>>(
  (ref) =>
      ref.watch(inkServiceProvider).watchIbcs(status: InkIbcStatus.received),
);

final inkAllIbcsProvider = StreamProvider<List<InkIbc>>(
  (ref) => ref.watch(inkServiceProvider).watchIbcs(),
);

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

final inkIbcsConsumedCountByColourProvider =
    Provider<Map<String, int>>((ref) {
  final all = ref.watch(inkAllIbcsProvider).valueOrNull ?? [];
  final range = ref.watch(inkOpenPeriodRangeProvider);
  return ibcConsumedCountByColour(all, range);
});

final inkOpenShipmentsProvider = StreamProvider<List<InkShipment>>(
  (ref) => ref.watch(inkServiceProvider).watchOpenIbcShipments(),
);

final inkOpenPalletShipmentsProvider = StreamProvider<List<InkShipment>>(
  (ref) => ref.watch(inkServiceProvider).watchOpenPalletShipments(),
);

final inkOpenPurchaseOrdersProvider = StreamProvider<List<InkPurchaseOrder>>(
  (ref) => ref.watch(inkServiceProvider).watchOpenPurchaseOrders(),
);

/// Production runs in the open period (server-scoped).
final inkProductionRunsProvider = StreamProvider<List<InkProductionRun>>((ref) {
  final from = ref.watch(inkOpenPeriodRangeProvider).fromExclusive;
  return ref
      .watch(inkServiceProvider)
      .watchProductionRuns(periodFromExclusive: from);
});

final inkProductionRunsCurrentPeriodProvider =
    Provider<AsyncValue<List<InkProductionRun>>>((ref) {
  return ref.watch(inkProductionRunsProvider);
});

/// Recoveries in the open period (server-scoped).
final inkRecentRecoveriesProvider = StreamProvider<List<InkTransaction>>((ref) {
  final from = ref.watch(inkOpenPeriodRangeProvider).fromExclusive;
  return ref.watch(inkServiceProvider).watchRecentRecoveries(
        limit: 100,
        periodFromExclusive: from,
      );
});

final inkRecentRecoveriesCurrentPeriodProvider =
    Provider<AsyncValue<List<InkTransaction>>>((ref) {
  return ref.watch(inkRecentRecoveriesProvider);
});

final inkActiveMeterPointsProvider = StreamProvider<List<InkMeterPoint>>(
  (ref) => ref.watch(inkServiceProvider).watchMeterPoints(activeOnly: true),
);

final inkAllMeterPointsProvider = StreamProvider<List<InkMeterPoint>>(
  (ref) => ref.watch(inkServiceProvider).watchMeterPoints(activeOnly: false),
);

final inkLatestMeterPointReadingsProvider =
    StreamProvider<Map<String, double>>(
  (ref) => ref.watch(inkServiceProvider).watchLatestMeterPointReadings(),
);

final inkRecentMeterPointReadingsProvider = StreamProvider<
    Map<String, List<({DateTime at, double reading})>>>(
  (ref) => ref.watch(inkServiceProvider).watchRecentMeterPointReadings(),
);

final inkMeterPointReadingsProvider = StreamProvider<
    List<({String pointId, double consumption, DateTime readingDate})>>((ref) {
  final from = ref.watch(inkOpenPeriodRangeProvider).fromExclusive;
  return ref
      .watch(inkServiceProvider)
      .watchMeterPointReadings(periodFromExclusive: from);
});

/// One-shot daily readings status for Home / Ink hub banners.
/// Show banner only when [InkDailyReadingsStatus.complete] is false.
/// Invalidate after submitting readings to refresh.
final inkDailyReadingsStatusProvider =
    FutureProvider.autoDispose<InkDailyReadingsStatus>((ref) {
  return ref.watch(inkServiceProvider).fetchDailyReadingsStatusOnce();
});

final inkTodayToloulPointIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(inkServiceProvider).watchTodayToloulPointIds(),
);

final inkTodayMeterItemCodesProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(inkServiceProvider).watchTodayInkMeterItemCodes(),
);

final inkRecentMeterSessionsProvider =
    StreamProvider<List<InkMeterSession>>((ref) {
  final from = ref.watch(inkOpenPeriodRangeProvider).fromExclusive;
  return ref
      .watch(inkServiceProvider)
      .watchRecentMeterSessions(periodFromExclusive: from);
});

/// Bounded count events for period boundary (not full history).
final inkCountEventsProvider = StreamProvider<List<InkCountEvent>>(
  (ref) => ref.watch(inkServiceProvider).watchCountEvents(limit: 20),
);

final inkMonthEndCountDatesProvider = Provider<List<DateTime>>((ref) {
  final events = ref.watch(inkCountEventsProvider).valueOrNull ?? [];
  final dates = events.map((e) => e.countDate).toList()..sort();
  return dates;
});
