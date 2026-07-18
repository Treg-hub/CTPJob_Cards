import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../constants/collections.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../models/lurgi_chemical_usage.dart';
import '../models/lurgi_daily_round.dart';
import '../models/lurgi_recycling_run.dart';
import '../utils/persona_audit.dart';
import 'resilient_stream.dart';

/// Lurgi department ops capture (Phase 1 morning round + Phase 2 multi-entry).
class LurgiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  void _guardWrite() => assertPersonaSubmitAllowed();

  DocumentReference<Map<String, dynamic>> _roundRef(String dateKey) =>
      _db.collection(Collections.lurgiDailyRounds).doc(dateKey);

  Stream<LurgiDailyRound?> watchRound(String dateKey) => resilientSnapshots(
        () => _roundRef(dateKey).snapshots(),
        debugName: 'lurgi_daily_rounds/$dateKey',
      ).map((snap) {
        if (!snap.exists) return null;
        try {
          return LurgiDailyRound.fromFirestore(snap);
        } catch (e) {
          debugPrint('Skipping unparseable lurgi_daily_rounds/$dateKey: $e');
          return null;
        }
      });

  Future<LurgiDailyRound?> fetchRound(String dateKey) async {
    final snap = await _roundRef(dateKey).get();
    if (!snap.exists) return null;
    return LurgiDailyRound.fromFirestore(snap);
  }

  /// Latest round strictly before [dateKey] (for meter baselines / deltas).
  Future<LurgiDailyRound?> fetchPreviousRound(String dateKey) async {
    final q = await _db
        .collection(Collections.lurgiDailyRounds)
        .where('date_key', isLessThan: dateKey)
        .orderBy('date_key', descending: true)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    try {
      return LurgiDailyRound.fromFirestore(q.docs.first);
    } catch (e) {
      debugPrint('Skipping unparseable previous lurgi round: $e');
      return null;
    }
  }

  /// Merge one or more morning sections into today's (or [round.dateKey]) doc.
  Future<void> saveRoundSections({
    required LurgiDailyRound round,
    required String actorClockNo,
    required String actorName,
    bool utilities = false,
    bool water = false,
    bool air = false,
    bool geyser = false,
    bool tanks = false,
  }) async {
    _guardWrite();
    if (!utilities && !water && !air && !geyser && !tanks) {
      throw ArgumentError('At least one section required');
    }
    final existing = await fetchRound(round.dateKey);
    final withRecorded = LurgiDailyRound(
      id: round.id,
      dateKey: round.dateKey,
      recordedAt: existing?.recordedAt ?? round.recordedAt,
      updatedAt: round.updatedAt,
      actorClockNo: actorClockNo,
      actorName: actorName,
      gasMechanical: round.gasMechanical,
      gasElectrical: round.gasElectrical,
      boilerFeed: round.boilerFeed,
      softener: round.softener,
      utilitiesAt: round.utilitiesAt,
      utilitiesByClock: round.utilitiesByClock,
      utilitiesByName: round.utilitiesByName,
      freshWater: round.freshWater,
      effluent: round.effluent,
      waterAt: round.waterAt,
      waterByClock: round.waterByClock,
      waterByName: round.waterByName,
      airMeter1: round.airMeter1,
      airMeter2: round.airMeter2,
      airAt: round.airAt,
      airByClock: round.airByClock,
      airByName: round.airByName,
      geyserTemp: round.geyserTemp,
      geyserComments: round.geyserComments,
      geyserAt: round.geyserAt,
      geyserByClock: round.geyserByClock,
      geyserByName: round.geyserByName,
      tank1Litres: round.tank1Litres,
      tank1Direction: round.tank1Direction,
      tank2Litres: round.tank2Litres,
      tank2Direction: round.tank2Direction,
      tank3Litres: round.tank3Litres,
      tank3Direction: round.tank3Direction,
      tanksAt: round.tanksAt,
      tanksByClock: round.tanksByClock,
      tanksByName: round.tanksByName,
    );
    final data = withRecorded.toMergeMap(
      includeUtilities: utilities,
      includeWater: water,
      includeAir: air,
      includeGeyser: geyser,
      includeTanks: tanks,
      actorClockNo: actorClockNo,
      actorName: actorName,
      now: DateTime.now(),
    );
    // Preserve first recorded_at on merge when doc exists.
    if (existing?.recordedAt != null) {
      data.remove('recorded_at');
    }
    await _roundRef(round.dateKey).set(data, SetOptions(merge: true));
  }

  /// Ink Factory recovery ledger rows (read-only for Lurgi).
  ///
  /// Scoped to the **open ink count period** when [periodFromExclusive] is set
  /// (from `ink_settings/config.latest_active_count_date`). Lurgi cannot read
  /// `ink_count_events`; settings is the period bound for mobile.
  Stream<List<InkTransaction>> watchInkFactoryRecoveries({
    int limit = 50,
    DateTime? periodFromExclusive,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection(Collections.inkTransactions)
        .where('type', isEqualTo: InkTxnType.recovery.value);
    if (periodFromExclusive != null) {
      q = q.where(
        'effective_at',
        isGreaterThan: Timestamp.fromDate(periodFromExclusive),
      );
    }
    return resilientSnapshots(
      () => q.orderBy('effective_at', descending: true).limit(limit).snapshots(),
      debugName: 'lurgi_ink_recoveries',
    ).map((s) {
      final list = <InkTransaction>[];
      for (final doc in s.docs) {
        try {
          final t = InkTransaction.fromFirestore(doc);
          if (t.voided) continue;
          // Defense in depth: open period is exclusive of count date.
          if (periodFromExclusive != null &&
              !t.effectiveAt.isAfter(periodFromExclusive)) {
            continue;
          }
          list.add(t);
        } catch (e) {
          debugPrint('Skipping unparseable recovery ${doc.id}: $e');
        }
      }
      return list;
    });
  }

  // ── Phase 2: effluent chemicals (multi-entry / day) ─────────────────────

  Stream<List<LurgiChemicalUsage>> watchChemicalUsageForDay(String dateKey) {
    return resilientSnapshots(
      () => _db
          .collection(Collections.lurgiChemicalUsage)
          .where('date_key', isEqualTo: dateKey)
          .orderBy('recorded_at', descending: true)
          .limit(100)
          .snapshots(),
      debugName: 'lurgi_chemical_usage/$dateKey',
    ).map((s) {
      final list = <LurgiChemicalUsage>[];
      for (final doc in s.docs) {
        try {
          final e = LurgiChemicalUsage.fromFirestore(doc);
          if (e.voided) continue;
          list.add(e);
        } catch (e) {
          debugPrint('Skipping unparseable chemical ${doc.id}: $e');
        }
      }
      return list;
    });
  }

  /// Open count-period chemical history.
  /// When [requirePeriodBound] is true and [periodFromExclusive] is null, returns empty
  /// (never falls back to unscoped / 60-day history).
  Stream<List<LurgiChemicalUsage>> watchChemicalUsageForOpenPeriod({
    DateTime? periodFromExclusive,
    int limit = 100,
    bool requirePeriodBound = true,
  }) {
    if (requirePeriodBound && periodFromExclusive == null) {
      return Stream.value(const <LurgiChemicalUsage>[]);
    }
    final from = periodFromExclusive ??
        DateTime.now().subtract(const Duration(days: 60));
    final q = _db
        .collection(Collections.lurgiChemicalUsage)
        .where('recorded_at', isGreaterThan: Timestamp.fromDate(from))
        .orderBy('recorded_at', descending: true)
        .limit(limit);
    return resilientSnapshots(
      () => q.snapshots(),
      debugName: 'lurgi_chemical_usage/period',
    ).map((s) {
      final list = <LurgiChemicalUsage>[];
      for (final doc in s.docs) {
        try {
          final e = LurgiChemicalUsage.fromFirestore(doc);
          if (e.voided) continue;
          // Client-side belt: recorded_at must be strictly after period bound.
          if (periodFromExclusive != null &&
              !e.recordedAt.isAfter(periodFromExclusive)) {
            continue;
          }
          list.add(e);
        } catch (e) {
          debugPrint('Skipping unparseable chemical ${doc.id}: $e');
        }
      }
      return list;
    });
  }

  Future<void> addChemicalUsage(LurgiChemicalUsage entry) async {
    _guardWrite();
    if (entry.totalKg <= 0) {
      throw ArgumentError('Enter at least one chemical quantity > 0');
    }
    await _db
        .collection(Collections.lurgiChemicalUsage)
        .add(entry.toFirestore());
  }

  // ── Phase 2: recycling machine (multi-run / day) ────────────────────────

  Stream<List<LurgiRecyclingRun>> watchRecyclingRunsForDay(String dateKey) {
    return resilientSnapshots(
      () => _db
          .collection(Collections.lurgiRecyclingRuns)
          .where('date_key', isEqualTo: dateKey)
          .orderBy('start_at', descending: true)
          .limit(50)
          .snapshots(),
      debugName: 'lurgi_recycling_runs/$dateKey',
    ).map((s) {
      final list = <LurgiRecyclingRun>[];
      for (final doc in s.docs) {
        try {
          final r = LurgiRecyclingRun.fromFirestore(doc);
          if (r.voided) continue;
          list.add(r);
        } catch (e) {
          debugPrint('Skipping unparseable recycling run ${doc.id}: $e');
        }
      }
      return list;
    });
  }

  Stream<List<LurgiRecyclingRun>> watchRecyclingRunsForOpenPeriod({
    DateTime? periodFromExclusive,
    int limit = 50,
    bool requirePeriodBound = true,
  }) {
    if (requirePeriodBound && periodFromExclusive == null) {
      return Stream.value(const <LurgiRecyclingRun>[]);
    }
    final from = periodFromExclusive ??
        DateTime.now().subtract(const Duration(days: 60));
    final q = _db
        .collection(Collections.lurgiRecyclingRuns)
        .where('start_at', isGreaterThan: Timestamp.fromDate(from))
        .orderBy('start_at', descending: true)
        .limit(limit);
    return resilientSnapshots(
      () => q.snapshots(),
      debugName: 'lurgi_recycling_runs/period',
    ).map((s) {
      final list = <LurgiRecyclingRun>[];
      for (final doc in s.docs) {
        try {
          final r = LurgiRecyclingRun.fromFirestore(doc);
          if (r.voided) continue;
          if (periodFromExclusive != null &&
              !r.startAt.isAfter(periodFromExclusive)) {
            continue;
          }
          list.add(r);
        } catch (e) {
          debugPrint('Skipping unparseable recycling run ${doc.id}: $e');
        }
      }
      return list;
    });
  }

  Future<void> addRecyclingRun(LurgiRecyclingRun run) async {
    _guardWrite();
    if (run.litresRecycled <= 0) {
      throw ArgumentError('Litres recycled must be greater than 0');
    }
    if (run.finishAt.isBefore(run.startAt)) {
      throw ArgumentError('Finish time must be after start time');
    }
    await _db.collection(Collections.lurgiRecyclingRuns).add(run.toFirestore());
  }
}
