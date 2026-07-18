import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_transaction.dart';
import '../models/lurgi_chemical_usage.dart';
import '../models/lurgi_daily_round.dart';
import '../models/lurgi_recycling_run.dart';
import '../services/lurgi_service.dart';
import 'ink_provider.dart';

final lurgiServiceProvider = Provider<LurgiService>((ref) => LurgiService());

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

/// Ink Factory recovery posts — view-only, open ink count period only.
final lurgiInkFactoryRecoveriesProvider =
    StreamProvider<List<InkTransaction>>((ref) {
  final from =
      ref.watch(inkSettingsProvider).valueOrNull?.latestActiveCountDate;
  return ref.watch(lurgiServiceProvider).watchInkFactoryRecoveries(
        limit: 50,
        periodFromExclusive: from,
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

/// Open count-period chemical history (since latest month-end count).
final lurgiPeriodChemicalUsageProvider =
    StreamProvider<List<LurgiChemicalUsage>>((ref) {
  final from =
      ref.watch(inkSettingsProvider).valueOrNull?.latestActiveCountDate;
  return ref.watch(lurgiServiceProvider).watchChemicalUsageForOpenPeriod(
        periodFromExclusive: from,
      );
});

final lurgiPeriodRecyclingRunsProvider =
    StreamProvider<List<LurgiRecyclingRun>>((ref) {
  final from =
      ref.watch(inkSettingsProvider).valueOrNull?.latestActiveCountDate;
  return ref.watch(lurgiServiceProvider).watchRecyclingRunsForOpenPeriod(
        periodFromExclusive: from,
      );
});
