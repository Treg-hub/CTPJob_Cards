import 'package:cloud_firestore/cloud_firestore.dart';

/// One morning-ops capture day for Lurgi (`lurgi_daily_rounds/{yyyy-MM-dd}`).
///
/// Sections: utilities (gas/boiler/softener), water (fresh/effluent),
/// air condenser, geyser, toloul tanks. Cumulative meters store dial readings;
/// deltas are derived vs the previous day document. Meter-reset flags and
/// multi-day span metadata are persisted for Pulse KPIs and audit.
class LurgiDailyRound {
  const LurgiDailyRound({
    this.id,
    required this.dateKey,
    this.recordedAt,
    this.updatedAt,
    this.actorClockNo,
    this.actorName,
    this.gasMechanical,
    this.gasElectrical,
    this.boilerFeed,
    this.softener,
    this.gasMechanicalReset = false,
    this.gasElectricalReset = false,
    this.boilerFeedReset = false,
    this.softenerReset = false,
    this.utilitiesAt,
    this.utilitiesByClock,
    this.utilitiesByName,
    this.freshWater,
    this.effluent,
    this.freshWaterReset = false,
    this.effluentReset = false,
    this.waterAt,
    this.waterByClock,
    this.waterByName,
    this.airMeter1,
    this.airMeter2,
    this.airMeter1Reset = false,
    this.airMeter2Reset = false,
    this.airAt,
    this.airByClock,
    this.airByName,
    this.geyserTemp,
    this.geyserComments,
    this.geyserAt,
    this.geyserByClock,
    this.geyserByName,
    this.tank1Litres,
    this.tank1Direction,
    this.tank2Litres,
    this.tank2Direction,
    this.tank3Litres,
    this.tank3Direction,
    this.tanksAt,
    this.tanksByClock,
    this.tanksByName,
    this.meterBaselineDateKey,
    this.meterSpanDays,
    this.meterSpanComment,
    this.chemicalsNoneToday = false,
    this.chemicalsNoneReason,
    this.chemicalsNoneAt,
    this.chemicalsNoneByClock,
    this.chemicalsNoneByName,
    this.recyclingNoneToday = false,
    this.recyclingNoneReason,
    this.recyclingNoneAt,
    this.recyclingNoneByClock,
    this.recyclingNoneByName,
  });

  final String? id;
  final String dateKey;
  final DateTime? recordedAt;
  final DateTime? updatedAt;
  final String? actorClockNo;
  final String? actorName;

  // ── Gas / boiler / softener ──────────────────────────────────────────────
  final double? gasMechanical;
  final double? gasElectrical;
  final double? boilerFeed;
  final double? softener;
  final bool gasMechanicalReset;
  final bool gasElectricalReset;
  final bool boilerFeedReset;
  final bool softenerReset;
  final DateTime? utilitiesAt;
  final String? utilitiesByClock;
  final String? utilitiesByName;

  // ── Fresh + effluent (one meter each) ────────────────────────────────────
  final double? freshWater;
  final double? effluent;
  final bool freshWaterReset;
  final bool effluentReset;
  final DateTime? waterAt;
  final String? waterByClock;
  final String? waterByName;

  // ── Air condenser ────────────────────────────────────────────────────────
  final double? airMeter1;
  final double? airMeter2;
  final bool airMeter1Reset;
  final bool airMeter2Reset;
  final DateTime? airAt;
  final String? airByClock;
  final String? airByName;

  // ── Geyser ───────────────────────────────────────────────────────────────
  final double? geyserTemp;
  final String? geyserComments;
  final DateTime? geyserAt;
  final String? geyserByClock;
  final String? geyserByName;

  // ── Toloul tanks (litres + in/out) ───────────────────────────────────────
  final double? tank1Litres;
  final String? tank1Direction; // 'in' | 'out'
  final double? tank2Litres;
  final String? tank2Direction;
  final double? tank3Litres;
  final String? tank3Direction;
  final DateTime? tanksAt;
  final String? tanksByClock;
  final String? tanksByName;

  // ── Multi-day baseline (when previous capture ≠ yesterday) ───────────────
  final String? meterBaselineDateKey;
  final int? meterSpanDays;
  final String? meterSpanComment;

  // ── As-needed day flags ──────────────────────────────────────────────────
  final bool chemicalsNoneToday;
  final String? chemicalsNoneReason;
  final DateTime? chemicalsNoneAt;
  final String? chemicalsNoneByClock;
  final String? chemicalsNoneByName;
  final bool recyclingNoneToday;
  final String? recyclingNoneReason;
  final DateTime? recyclingNoneAt;
  final String? recyclingNoneByClock;
  final String? recyclingNoneByName;

  bool get utilitiesComplete =>
      gasMechanical != null &&
      gasElectrical != null &&
      boilerFeed != null &&
      softener != null;

  bool get waterComplete => freshWater != null && effluent != null;

  bool get airComplete => airMeter1 != null && airMeter2 != null;

  bool get geyserComplete => geyserTemp != null;

  bool get tanksComplete =>
      tank1Litres != null &&
      tank1Direction != null &&
      tank2Litres != null &&
      tank2Direction != null &&
      tank3Litres != null &&
      tank3Direction != null;

  /// Morning-round daily sections (excludes ink Daily Readings).
  bool get morningComplete =>
      utilitiesComplete &&
      waterComplete &&
      airComplete &&
      geyserComplete &&
      tanksComplete;

  int get completedSectionCount {
    var n = 0;
    if (utilitiesComplete) n++;
    if (waterComplete) n++;
    if (airComplete) n++;
    if (geyserComplete) n++;
    if (tanksComplete) n++;
    return n;
  }

  static const int totalSections = 5;

  factory LurgiDailyRound.empty(String dateKey) =>
      LurgiDailyRound(dateKey: dateKey);

  factory LurgiDailyRound.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return LurgiDailyRound(
      id: doc.id,
      dateKey: d['date_key'] as String? ?? doc.id,
      recordedAt: _ts(d['recorded_at']),
      updatedAt: _ts(d['updated_at']),
      actorClockNo: d['actor_clock_no'] as String?,
      actorName: d['actor_name'] as String?,
      gasMechanical: _num(d['gas_mechanical']),
      gasElectrical: _num(d['gas_electrical']),
      boilerFeed: _num(d['boiler_feed']),
      softener: _num(d['softener']),
      gasMechanicalReset: d['gas_mechanical_reset'] as bool? ?? false,
      gasElectricalReset: d['gas_electrical_reset'] as bool? ?? false,
      boilerFeedReset: d['boiler_feed_reset'] as bool? ?? false,
      softenerReset: d['softener_reset'] as bool? ?? false,
      utilitiesAt: _ts(d['utilities_at']),
      utilitiesByClock: d['utilities_by_clock'] as String?,
      utilitiesByName: d['utilities_by_name'] as String?,
      freshWater: _num(d['fresh_water']),
      effluent: _num(d['effluent']),
      freshWaterReset: d['fresh_water_reset'] as bool? ?? false,
      effluentReset: d['effluent_reset'] as bool? ?? false,
      waterAt: _ts(d['water_at']),
      waterByClock: d['water_by_clock'] as String?,
      waterByName: d['water_by_name'] as String?,
      airMeter1: _num(d['air_meter_1']),
      airMeter2: _num(d['air_meter_2']),
      airMeter1Reset: d['air_meter_1_reset'] as bool? ?? false,
      airMeter2Reset: d['air_meter_2_reset'] as bool? ?? false,
      airAt: _ts(d['air_at']),
      airByClock: d['air_by_clock'] as String?,
      airByName: d['air_by_name'] as String?,
      geyserTemp: _num(d['geyser_temp']),
      geyserComments: d['geyser_comments'] as String?,
      geyserAt: _ts(d['geyser_at']),
      geyserByClock: d['geyser_by_clock'] as String?,
      geyserByName: d['geyser_by_name'] as String?,
      tank1Litres: _num(d['tank1_litres']),
      tank1Direction: d['tank1_direction'] as String?,
      tank2Litres: _num(d['tank2_litres']),
      tank2Direction: d['tank2_direction'] as String?,
      tank3Litres: _num(d['tank3_litres']),
      tank3Direction: d['tank3_direction'] as String?,
      tanksAt: _ts(d['tanks_at']),
      tanksByClock: d['tanks_by_clock'] as String?,
      tanksByName: d['tanks_by_name'] as String?,
      meterBaselineDateKey: d['meter_baseline_date_key'] as String?,
      meterSpanDays: (d['meter_span_days'] as num?)?.toInt(),
      meterSpanComment: d['meter_span_comment'] as String?,
      chemicalsNoneToday: d['chemicals_none_today'] as bool? ?? false,
      chemicalsNoneReason: d['chemicals_none_reason'] as String?,
      chemicalsNoneAt: _ts(d['chemicals_none_at']),
      chemicalsNoneByClock: d['chemicals_none_by_clock'] as String?,
      chemicalsNoneByName: d['chemicals_none_by_name'] as String?,
      recyclingNoneToday: d['recycling_none_today'] as bool? ?? false,
      recyclingNoneReason: d['recycling_none_reason'] as String?,
      recyclingNoneAt: _ts(d['recycling_none_at']),
      recyclingNoneByClock: d['recycling_none_by_clock'] as String?,
      recyclingNoneByName: d['recycling_none_by_name'] as String?,
    );
  }

  /// Partial map for set(merge: true). Only non-null section fields.
  Map<String, dynamic> toMergeMap({
    required bool includeUtilities,
    required bool includeWater,
    required bool includeAir,
    required bool includeGeyser,
    required bool includeTanks,
    required String actorClockNo,
    required String actorName,
    required DateTime now,
    bool includeSpan = false,
    bool includeNoneFlags = false,
  }) {
    final m = <String, dynamic>{
      'date_key': dateKey,
      'updated_at': FieldValue.serverTimestamp(),
      'actor_clock_no': actorClockNo,
      'actor_name': actorName,
    };
    if (recordedAt == null) {
      m['recorded_at'] = FieldValue.serverTimestamp();
    }
    if (includeUtilities) {
      m['gas_mechanical'] = gasMechanical;
      m['gas_electrical'] = gasElectrical;
      m['boiler_feed'] = boilerFeed;
      m['softener'] = softener;
      m['gas_mechanical_reset'] = gasMechanicalReset;
      m['gas_electrical_reset'] = gasElectricalReset;
      m['boiler_feed_reset'] = boilerFeedReset;
      m['softener_reset'] = softenerReset;
      m['utilities_at'] = Timestamp.fromDate(now);
      m['utilities_by_clock'] = actorClockNo;
      m['utilities_by_name'] = actorName;
    }
    if (includeWater) {
      m['fresh_water'] = freshWater;
      m['effluent'] = effluent;
      m['fresh_water_reset'] = freshWaterReset;
      m['effluent_reset'] = effluentReset;
      m['water_at'] = Timestamp.fromDate(now);
      m['water_by_clock'] = actorClockNo;
      m['water_by_name'] = actorName;
    }
    if (includeAir) {
      m['air_meter_1'] = airMeter1;
      m['air_meter_2'] = airMeter2;
      m['air_meter_1_reset'] = airMeter1Reset;
      m['air_meter_2_reset'] = airMeter2Reset;
      m['air_at'] = Timestamp.fromDate(now);
      m['air_by_clock'] = actorClockNo;
      m['air_by_name'] = actorName;
    }
    if (includeGeyser) {
      m['geyser_temp'] = geyserTemp;
      m['geyser_comments'] = geyserComments;
      m['geyser_at'] = Timestamp.fromDate(now);
      m['geyser_by_clock'] = actorClockNo;
      m['geyser_by_name'] = actorName;
    }
    if (includeTanks) {
      m['tank1_litres'] = tank1Litres;
      m['tank1_direction'] = tank1Direction;
      m['tank2_litres'] = tank2Litres;
      m['tank2_direction'] = tank2Direction;
      m['tank3_litres'] = tank3Litres;
      m['tank3_direction'] = tank3Direction;
      m['tanks_at'] = Timestamp.fromDate(now);
      m['tanks_by_clock'] = actorClockNo;
      m['tanks_by_name'] = actorName;
    }
    if (includeSpan) {
      if (meterBaselineDateKey != null) {
        m['meter_baseline_date_key'] = meterBaselineDateKey;
      }
      if (meterSpanDays != null) {
        m['meter_span_days'] = meterSpanDays;
      }
      if (meterSpanComment != null && meterSpanComment!.trim().isNotEmpty) {
        m['meter_span_comment'] = meterSpanComment!.trim();
      }
    }
    if (includeNoneFlags) {
      m['chemicals_none_today'] = chemicalsNoneToday;
      if (chemicalsNoneToday) {
        m['chemicals_none_reason'] = chemicalsNoneReason;
        m['chemicals_none_at'] = Timestamp.fromDate(now);
        m['chemicals_none_by_clock'] = actorClockNo;
        m['chemicals_none_by_name'] = actorName;
      } else {
        m['chemicals_none_reason'] = FieldValue.delete();
        m['chemicals_none_at'] = FieldValue.delete();
        m['chemicals_none_by_clock'] = FieldValue.delete();
        m['chemicals_none_by_name'] = FieldValue.delete();
      }
      m['recycling_none_today'] = recyclingNoneToday;
      if (recyclingNoneToday) {
        m['recycling_none_reason'] = recyclingNoneReason;
        m['recycling_none_at'] = Timestamp.fromDate(now);
        m['recycling_none_by_clock'] = actorClockNo;
        m['recycling_none_by_name'] = actorName;
      } else {
        m['recycling_none_reason'] = FieldValue.delete();
        m['recycling_none_at'] = FieldValue.delete();
        m['recycling_none_by_clock'] = FieldValue.delete();
        m['recycling_none_by_name'] = FieldValue.delete();
      }
    }
    return m;
  }

  LurgiDailyRound copyWith({
    double? gasMechanical,
    double? gasElectrical,
    double? boilerFeed,
    double? softener,
    bool? gasMechanicalReset,
    bool? gasElectricalReset,
    bool? boilerFeedReset,
    bool? softenerReset,
    double? freshWater,
    double? effluent,
    bool? freshWaterReset,
    bool? effluentReset,
    double? airMeter1,
    double? airMeter2,
    bool? airMeter1Reset,
    bool? airMeter2Reset,
    double? geyserTemp,
    String? geyserComments,
    double? tank1Litres,
    String? tank1Direction,
    double? tank2Litres,
    String? tank2Direction,
    double? tank3Litres,
    String? tank3Direction,
    String? meterBaselineDateKey,
    int? meterSpanDays,
    String? meterSpanComment,
    bool? chemicalsNoneToday,
    String? chemicalsNoneReason,
    bool? recyclingNoneToday,
    String? recyclingNoneReason,
  }) {
    return LurgiDailyRound(
      id: id,
      dateKey: dateKey,
      recordedAt: recordedAt,
      updatedAt: updatedAt,
      actorClockNo: actorClockNo,
      actorName: actorName,
      gasMechanical: gasMechanical ?? this.gasMechanical,
      gasElectrical: gasElectrical ?? this.gasElectrical,
      boilerFeed: boilerFeed ?? this.boilerFeed,
      softener: softener ?? this.softener,
      gasMechanicalReset: gasMechanicalReset ?? this.gasMechanicalReset,
      gasElectricalReset: gasElectricalReset ?? this.gasElectricalReset,
      boilerFeedReset: boilerFeedReset ?? this.boilerFeedReset,
      softenerReset: softenerReset ?? this.softenerReset,
      utilitiesAt: utilitiesAt,
      utilitiesByClock: utilitiesByClock,
      utilitiesByName: utilitiesByName,
      freshWater: freshWater ?? this.freshWater,
      effluent: effluent ?? this.effluent,
      freshWaterReset: freshWaterReset ?? this.freshWaterReset,
      effluentReset: effluentReset ?? this.effluentReset,
      waterAt: waterAt,
      waterByClock: waterByClock,
      waterByName: waterByName,
      airMeter1: airMeter1 ?? this.airMeter1,
      airMeter2: airMeter2 ?? this.airMeter2,
      airMeter1Reset: airMeter1Reset ?? this.airMeter1Reset,
      airMeter2Reset: airMeter2Reset ?? this.airMeter2Reset,
      airAt: airAt,
      airByClock: airByClock,
      airByName: airByName,
      geyserTemp: geyserTemp ?? this.geyserTemp,
      geyserComments: geyserComments ?? this.geyserComments,
      geyserAt: geyserAt,
      geyserByClock: geyserByClock,
      geyserByName: geyserByName,
      tank1Litres: tank1Litres ?? this.tank1Litres,
      tank1Direction: tank1Direction ?? this.tank1Direction,
      tank2Litres: tank2Litres ?? this.tank2Litres,
      tank2Direction: tank2Direction ?? this.tank2Direction,
      tank3Litres: tank3Litres ?? this.tank3Litres,
      tank3Direction: tank3Direction ?? this.tank3Direction,
      tanksAt: tanksAt,
      tanksByClock: tanksByClock,
      tanksByName: tanksByName,
      meterBaselineDateKey: meterBaselineDateKey ?? this.meterBaselineDateKey,
      meterSpanDays: meterSpanDays ?? this.meterSpanDays,
      meterSpanComment: meterSpanComment ?? this.meterSpanComment,
      chemicalsNoneToday: chemicalsNoneToday ?? this.chemicalsNoneToday,
      chemicalsNoneReason: chemicalsNoneReason ?? this.chemicalsNoneReason,
      chemicalsNoneAt: chemicalsNoneAt,
      chemicalsNoneByClock: chemicalsNoneByClock,
      chemicalsNoneByName: chemicalsNoneByName,
      recyclingNoneToday: recyclingNoneToday ?? this.recyclingNoneToday,
      recyclingNoneReason: recyclingNoneReason ?? this.recyclingNoneReason,
      recyclingNoneAt: recyclingNoneAt,
      recyclingNoneByClock: recyclingNoneByClock,
      recyclingNoneByName: recyclingNoneByName,
    );
  }

  static double? _num(dynamic v) => (v as num?)?.toDouble();

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

/// Calendar day key in local time: `yyyy-MM-dd`.
String lurgiDateKey([DateTime? day]) {
  final d = day ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dayNum = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dayNum';
}

/// Days between two `yyyy-MM-dd` keys (calendar). Null if unparseable.
int? lurgiDateKeyDaySpan(String earlier, String later) {
  final a = DateTime.tryParse(earlier);
  final b = DateTime.tryParse(later);
  if (a == null || b == null) return null;
  return b.difference(DateTime(a.year, a.month, a.day)).inDays;
}

/// Yesterday's date key relative to [day] (local).
String lurgiYesterdayDateKey([DateTime? day]) {
  final d = day ?? DateTime.now();
  final y = DateTime(d.year, d.month, d.day).subtract(const Duration(days: 1));
  return lurgiDateKey(y);
}

/// Cumulative meter delta. Null previous → null delta (first capture).
/// [reset] treats [current] as the full post-reset usage.
double? lurgiMeterDelta(double? previous, double current, {bool reset = false}) {
  if (reset) return current;
  if (previous == null) return null;
  return current - previous;
}
