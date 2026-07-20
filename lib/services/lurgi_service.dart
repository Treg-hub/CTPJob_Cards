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

/// Page size for open-period list UIs (chemicals / recycling / recovery).
const int kLurgiPeriodPageSize = 40;

/// Lurgi department ops capture (morning sections + multi-entry logs).
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

  /// Morning rounds in the open count period (date_key ≥ period bound day).
  ///
  /// [periodFromExclusive] is the latest count date; rounds on/after the next
  /// calendar day are included. Uses date_key string compare (yyyy-MM-dd).
  Future<List<LurgiDailyRound>> fetchRoundsForOpenPeriod({
    required DateTime periodFromExclusive,
    int limit = 120,
  }) async {
    final fromKey = lurgiDateKey(periodFromExclusive);
    final q = await _db
        .collection(Collections.lurgiDailyRounds)
        .where('date_key', isGreaterThan: fromKey)
        .orderBy('date_key', descending: true)
        .limit(limit)
        .get();
    final list = <LurgiDailyRound>[];
    for (final doc in q.docs) {
      try {
        list.add(LurgiDailyRound.fromFirestore(doc));
      } catch (e) {
        debugPrint('Skipping unparseable period round ${doc.id}: $e');
      }
    }
    return list;
  }

  /// Merge one or more morning sections into today's (or [round.dateKey]) doc.
  ///
  /// [effectiveAt] stamps section `*_at` fields (admin date override only).
  Future<void> saveRoundSections({
    required LurgiDailyRound round,
    required String actorClockNo,
    required String actorName,
    bool utilities = false,
    bool water = false,
    bool air = false,
    bool geyser = false,
    bool tanks = false,
    DateTime? effectiveAt,
  }) async {
    _guardWrite();
    if (!utilities && !water && !air && !geyser && !tanks) {
      throw ArgumentError('At least one section required');
    }
    final now = effectiveAt ?? DateTime.now();
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
      gasMechanicalReset: round.gasMechanicalReset,
      gasElectricalReset: round.gasElectricalReset,
      boilerFeedReset: round.boilerFeedReset,
      softenerReset: round.softenerReset,
      utilitiesAt: round.utilitiesAt,
      utilitiesByClock: round.utilitiesByClock,
      utilitiesByName: round.utilitiesByName,
      freshWater: round.freshWater,
      effluent: round.effluent,
      freshWaterReset: round.freshWaterReset,
      effluentReset: round.effluentReset,
      waterAt: round.waterAt,
      waterByClock: round.waterByClock,
      waterByName: round.waterByName,
      airMeter1: round.airMeter1,
      airMeter2: round.airMeter2,
      airMeter1Reset: round.airMeter1Reset,
      airMeter2Reset: round.airMeter2Reset,
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
      meterBaselineDateKey: round.meterBaselineDateKey,
      meterSpanDays: round.meterSpanDays,
      meterSpanComment: round.meterSpanComment,
      chemicalsNoneToday:
          existing?.chemicalsNoneToday ?? round.chemicalsNoneToday,
      recyclingNoneToday:
          existing?.recyclingNoneToday ?? round.recyclingNoneToday,
    );
    final data = withRecorded.toMergeMap(
      includeUtilities: utilities,
      includeWater: water,
      includeAir: air,
      includeGeyser: geyser,
      includeTanks: tanks,
      actorClockNo: actorClockNo,
      actorName: actorName,
      now: now,
      includeSpan: round.meterSpanDays != null ||
          (round.meterSpanComment != null &&
              round.meterSpanComment!.trim().isNotEmpty),
    );
    if (existing?.recordedAt != null) {
      data.remove('recorded_at');
    } else if (effectiveAt != null) {
      data['recorded_at'] = Timestamp.fromDate(effectiveAt);
    }
    await _roundRef(round.dateKey).set(data, SetOptions(merge: true));
  }

  /// Mark chemicals / recycling as intentionally none for [dateKey].
  Future<void> setNoneTodayFlags({
    required String dateKey,
    required String actorClockNo,
    required String actorName,
    bool? chemicalsNoneToday,
    String? chemicalsNoneReason,
    bool? recyclingNoneToday,
    String? recyclingNoneReason,
    DateTime? effectiveAt,
  }) async {
    _guardWrite();
    final now = effectiveAt ?? DateTime.now();
    final existing = await fetchRound(dateKey);
    final round = LurgiDailyRound(
      dateKey: dateKey,
      recordedAt: existing?.recordedAt,
      chemicalsNoneToday:
          chemicalsNoneToday ?? existing?.chemicalsNoneToday ?? false,
      chemicalsNoneReason: chemicalsNoneReason ?? existing?.chemicalsNoneReason,
      recyclingNoneToday:
          recyclingNoneToday ?? existing?.recyclingNoneToday ?? false,
      recyclingNoneReason:
          recyclingNoneReason ?? existing?.recyclingNoneReason,
    );
    final data = round.toMergeMap(
      includeUtilities: false,
      includeWater: false,
      includeAir: false,
      includeGeyser: false,
      includeTanks: false,
      actorClockNo: actorClockNo,
      actorName: actorName,
      now: now,
      includeNoneFlags: true,
    );
    if (existing?.recordedAt != null) {
      data.remove('recorded_at');
    }
    await _roundRef(dateKey).set(data, SetOptions(merge: true));
  }

  /// Clear chemicals_none when a dose is logged.
  Future<void> clearChemicalsNoneIfSet(String dateKey) async {
    final existing = await fetchRound(dateKey);
    if (existing == null || !existing.chemicalsNoneToday) return;
    await _roundRef(dateKey).set({
      'chemicals_none_today': false,
      'chemicals_none_reason': FieldValue.delete(),
      'chemicals_none_at': FieldValue.delete(),
      'chemicals_none_by_clock': FieldValue.delete(),
      'chemicals_none_by_name': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearRecyclingNoneIfSet(String dateKey) async {
    final existing = await fetchRound(dateKey);
    if (existing == null || !existing.recyclingNoneToday) return;
    await _roundRef(dateKey).set({
      'recycling_none_today': false,
      'recycling_none_reason': FieldValue.delete(),
      'recycling_none_at': FieldValue.delete(),
      'recycling_none_by_clock': FieldValue.delete(),
      'recycling_none_by_name': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Ink Factory recovery ledger rows (read-only for Lurgi).
  Stream<List<InkTransaction>> watchInkFactoryRecoveries({
    int limit = 50,
    DateTime? periodFromExclusive,
    DocumentSnapshot? startAfter,
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
    q = q.orderBy('effective_at', descending: true).limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return resilientSnapshots(
      () => q.snapshots(),
      debugName: 'lurgi_ink_recoveries',
    ).map((s) {
      final list = <InkTransaction>[];
      for (final doc in s.docs) {
        try {
          final t = InkTransaction.fromFirestore(doc);
          if (t.voided) continue;
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

  /// One-shot recovery page (for load-more pagination).
  Future<({List<InkTransaction> rows, DocumentSnapshot? lastDoc})>
      fetchInkFactoryRecoveriesPage({
    required DateTime periodFromExclusive,
    int limit = kLurgiPeriodPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection(Collections.inkTransactions)
        .where('type', isEqualTo: InkTxnType.recovery.value)
        .where(
          'effective_at',
          isGreaterThan: Timestamp.fromDate(periodFromExclusive),
        )
        .orderBy('effective_at', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final s = await q.get();
    final list = <InkTransaction>[];
    for (final doc in s.docs) {
      try {
        final t = InkTransaction.fromFirestore(doc);
        if (t.voided) continue;
        if (!t.effectiveAt.isAfter(periodFromExclusive)) continue;
        list.add(t);
      } catch (e) {
        debugPrint('Skipping unparseable recovery ${doc.id}: $e');
      }
    }
    return (
      rows: list,
      lastDoc: s.docs.isEmpty ? null : s.docs.last,
    );
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

  Stream<List<LurgiChemicalUsage>> watchChemicalUsageForOpenPeriod({
    DateTime? periodFromExclusive,
    int limit = kLurgiPeriodPageSize,
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

  Future<({List<LurgiChemicalUsage> rows, DocumentSnapshot? lastDoc})>
      fetchChemicalUsagePage({
    required DateTime periodFromExclusive,
    int limit = kLurgiPeriodPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection(Collections.lurgiChemicalUsage)
        .where(
          'recorded_at',
          isGreaterThan: Timestamp.fromDate(periodFromExclusive),
        )
        .orderBy('recorded_at', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final s = await q.get();
    final list = <LurgiChemicalUsage>[];
    for (final doc in s.docs) {
      try {
        final e = LurgiChemicalUsage.fromFirestore(doc);
        if (e.voided) continue;
        if (!e.recordedAt.isAfter(periodFromExclusive)) continue;
        list.add(e);
      } catch (e) {
        debugPrint('Skipping unparseable chemical ${doc.id}: $e');
      }
    }
    return (
      rows: list,
      lastDoc: s.docs.isEmpty ? null : s.docs.last,
    );
  }

  /// Full-period sum (paged until exhausted) for honest totals.
  Future<LurgiChemicalDayTotals> sumChemicalUsageForOpenPeriod(
    DateTime periodFromExclusive,
  ) async {
    DocumentSnapshot? cursor;
    final all = <LurgiChemicalUsage>[];
    while (true) {
      final page = await fetchChemicalUsagePage(
        periodFromExclusive: periodFromExclusive,
        limit: 100,
        startAfter: cursor,
      );
      all.addAll(page.rows);
      if (page.lastDoc == null || page.rows.length < 100) break;
      cursor = page.lastDoc;
      if (all.length > 2000) break; // safety
    }
    return LurgiChemicalDayTotals.fromEntries(all);
  }

  Future<void> addChemicalUsage(LurgiChemicalUsage entry) async {
    _guardWrite();
    if (entry.totalKg <= 0) {
      throw ArgumentError('Enter at least one chemical quantity > 0');
    }
    await _db
        .collection(Collections.lurgiChemicalUsage)
        .add(entry.toFirestore());
    await clearChemicalsNoneIfSet(entry.dateKey);
  }

  Future<void> requestChemicalVoid({
    required String docId,
    required String reason,
    required String actorClockNo,
    required String actorName,
  }) async {
    _guardWrite();
    final r = reason.trim();
    if (r.length < 3) {
      throw ArgumentError('Enter a short reason (at least 3 characters)');
    }
    await _db.collection(Collections.lurgiChemicalUsage).doc(docId).update({
      'void_requested': true,
      'void_request_reason': r,
      'void_requested_at': FieldValue.serverTimestamp(),
      'void_requested_by_clock_no': actorClockNo,
      'void_requested_by_name': actorName,
    });
  }

  Future<void> cancelChemicalVoidRequest(String docId) async {
    _guardWrite();
    await _db.collection(Collections.lurgiChemicalUsage).doc(docId).update({
      'void_requested': false,
      'void_request_reason': FieldValue.delete(),
      'void_requested_at': FieldValue.delete(),
      'void_requested_by_clock_no': FieldValue.delete(),
      'void_requested_by_name': FieldValue.delete(),
    });
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
    int limit = kLurgiPeriodPageSize,
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

  Future<({List<LurgiRecyclingRun> rows, DocumentSnapshot? lastDoc})>
      fetchRecyclingRunsPage({
    required DateTime periodFromExclusive,
    int limit = kLurgiPeriodPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection(Collections.lurgiRecyclingRuns)
        .where(
          'start_at',
          isGreaterThan: Timestamp.fromDate(periodFromExclusive),
        )
        .orderBy('start_at', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    final s = await q.get();
    final list = <LurgiRecyclingRun>[];
    for (final doc in s.docs) {
      try {
        final r = LurgiRecyclingRun.fromFirestore(doc);
        if (r.voided) continue;
        if (!r.startAt.isAfter(periodFromExclusive)) continue;
        list.add(r);
      } catch (e) {
        debugPrint('Skipping unparseable recycling run ${doc.id}: $e');
      }
    }
    return (
      rows: list,
      lastDoc: s.docs.isEmpty ? null : s.docs.last,
    );
  }

  Future<LurgiRecyclingDaySummary> sumRecyclingForOpenPeriod(
    DateTime periodFromExclusive,
  ) async {
    DocumentSnapshot? cursor;
    final all = <LurgiRecyclingRun>[];
    while (true) {
      final page = await fetchRecyclingRunsPage(
        periodFromExclusive: periodFromExclusive,
        limit: 100,
        startAfter: cursor,
      );
      all.addAll(page.rows);
      if (page.lastDoc == null || page.rows.length < 100) break;
      cursor = page.lastDoc;
      if (all.length > 2000) break;
    }
    return LurgiRecyclingDaySummary.fromRuns(all);
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
    await clearRecyclingNoneIfSet(run.dateKey);
  }

  Future<void> requestRecyclingVoid({
    required String docId,
    required String reason,
    required String actorClockNo,
    required String actorName,
  }) async {
    _guardWrite();
    final r = reason.trim();
    if (r.length < 3) {
      throw ArgumentError('Enter a short reason (at least 3 characters)');
    }
    await _db.collection(Collections.lurgiRecyclingRuns).doc(docId).update({
      'void_requested': true,
      'void_request_reason': r,
      'void_requested_at': FieldValue.serverTimestamp(),
      'void_requested_by_clock_no': actorClockNo,
      'void_requested_by_name': actorName,
    });
  }

  Future<void> cancelRecyclingVoidRequest(String docId) async {
    _guardWrite();
    await _db.collection(Collections.lurgiRecyclingRuns).doc(docId).update({
      'void_requested': false,
      'void_request_reason': FieldValue.delete(),
      'void_requested_at': FieldValue.delete(),
      'void_requested_by_clock_no': FieldValue.delete(),
      'void_requested_by_name': FieldValue.delete(),
    });
  }
}
