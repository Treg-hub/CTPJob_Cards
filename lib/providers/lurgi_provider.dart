import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_settings.dart';
import '../models/ink_transaction.dart';
import '../models/lurgi_chemical_usage.dart';
import '../models/lurgi_daily_round.dart';
import '../models/lurgi_recycling_run.dart';
import '../services/lurgi_service.dart';
import 'ink_provider.dart';

final lurgiServiceProvider = Provider<LurgiService>((ref) => LurgiService());

/// Open ink count lower bound (`latest_active_count_date`). Null until settings
/// load; after load, null means no count on file (lists stay empty — do not
/// fall back to unscoped history).
final lurgiOpenPeriodFromProvider = Provider<AsyncValue<DateTime?>>((ref) {
  return ref.watch(inkSettingsProvider).whenData((s) => s.latestActiveCountDate);
});

/// Today's morning-round document (null until first section saved).
final lurgiTodayRoundProvider = StreamProvider<LurgiDailyRound?>((ref) {
  final key = lurgiDateKey();
  return ref.watch(lurgiServiceProvider).watchRound(key);
});

/// Previous day baseline for cumulative meter deltas.
final lurgiPreviousRoundProvider =
    FutureProvider.family<LurgiDailyRound?, String>((ref, dateKey) {
  return ref.watch(lurgiServiceProvider).fetchPreviousRound(dateKey);
});

/// Ink Factory recovery posts — view-only, **open ink count period only**.
/// Waits for ink_settings so we never briefly stream unscoped recoveries.
final lurgiInkFactoryRecoveriesProvider =
    StreamProvider<List<InkTransaction>>((ref) {
  final periodAsync = ref.watch(lurgiOpenPeriodFromProvider);
  return periodAsync.when(
    loading: () => Stream.value(const <InkTransaction>[]),
    error: (_, __) => Stream.value(const <InkTransaction>[]),
    data: (from) {
      if (from == null) return Stream.value(const <InkTransaction>[]);
      return ref.watch(lurgiServiceProvider).watchInkFactoryRecoveries(
            limit: 100,
            periodFromExclusive: from,
          );
    },
  );
});

/// Today's effluent chemical entries (newest first).
final lurgiTodayChemicalUsageProvider =
    StreamProvider<List<LurgiChemicalUsage>>((ref) {
  final key = lurgiDateKey();
  return ref.watch(lurgiServiceProvider).watchChemicalUsageForDay(key);
});

final lurgiTodayChemicalTotalsProvider = Provider<LurgiChemicalDayTotals>((ref) {
  final entries = ref.watch(lurgiTodayChemicalUsageProvider).valueOrNull ?? [];
  return LurgiChemicalDayTotals.fromEntries(entries);
});

/// Today's recycling machine runs (newest first).
final lurgiTodayRecyclingRunsProvider =
    StreamProvider<List<LurgiRecyclingRun>>((ref) {
  final key = lurgiDateKey();
  return ref.watch(lurgiServiceProvider).watchRecyclingRunsForDay(key);
});

final lurgiTodayRecyclingSummaryProvider =
    Provider<LurgiRecyclingDaySummary>((ref) {
  final runs = ref.watch(lurgiTodayRecyclingRunsProvider).valueOrNull ?? [];
  return LurgiRecyclingDaySummary.fromRuns(runs);
});

/// Open count-period chemical history (requires `latest_active_count_date`).
final lurgiPeriodChemicalUsageProvider =
    StreamProvider<List<LurgiChemicalUsage>>((ref) {
  final periodAsync = ref.watch(lurgiOpenPeriodFromProvider);
  return periodAsync.when(
    loading: () => Stream.value(const <LurgiChemicalUsage>[]),
    error: (_, __) => Stream.value(const <LurgiChemicalUsage>[]),
    data: (from) {
      if (from == null) return Stream.value(const <LurgiChemicalUsage>[]);
      return ref.watch(lurgiServiceProvider).watchChemicalUsageForOpenPeriod(
            periodFromExclusive: from,
            requirePeriodBound: true,
          );
    },
  );
});

/// Open count-period recycling history (requires `latest_active_count_date`).
final lurgiPeriodRecyclingRunsProvider =
    StreamProvider<List<LurgiRecyclingRun>>((ref) {
  final periodAsync = ref.watch(lurgiOpenPeriodFromProvider);
  return periodAsync.when(
    loading: () => Stream.value(const <LurgiRecyclingRun>[]),
    error: (_, __) => Stream.value(const <LurgiRecyclingRun>[]),
    data: (from) {
      if (from == null) return Stream.value(const <LurgiRecyclingRun>[]);
      return ref.watch(lurgiServiceProvider).watchRecyclingRunsForOpenPeriod(
            periodFromExclusive: from,
            requirePeriodBound: true,
          );
    },
  );
});

/// Period totals for chemicals (all days in open count window).
final lurgiPeriodChemicalTotalsProvider = Provider<LurgiChemicalDayTotals>((ref) {
  final entries = ref.watch(lurgiPeriodChemicalUsageProvider).valueOrNull ?? [];
  return LurgiChemicalDayTotals.fromEntries(entries);
});

final lurgiPeriodRecyclingSummaryProvider =
    Provider<LurgiRecyclingDaySummary>((ref) {
  final runs = ref.watch(lurgiPeriodRecyclingRunsProvider).valueOrNull ?? [];
  return LurgiRecyclingDaySummary.fromRuns(runs);
});

/// Label helper for open period banner (null if still loading settings).
String? lurgiOpenPeriodLabel(InkSettings? settings) {
  final from = settings?.latestActiveCountDate;
  if (from == null) return null;
  final y = from.year.toString().padLeft(4, '0');
  final m = from.month.toString().padLeft(2, '0');
  final d = from.day.toString().padLeft(2, '0');
  return 'Open ink count period since $y-$m-$d';
}
