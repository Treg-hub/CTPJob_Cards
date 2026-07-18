import 'package:cloud_firestore/cloud_firestore.dart';

/// One morning-ops capture day for Lurgi (`lurgi_daily_rounds/{yyyy-MM-dd}`).
///
/// Phase 1 sections: utilities (gas/boiler/softener), water (fresh/effluent),
/// air condenser, geyser, toloul tanks. Cumulative meters store dial readings;
/// deltas are derived vs the previous day document.
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
    this.utilitiesAt,
    this.utilitiesByClock,
    this.utilitiesByName,
    this.freshWater,
    this.effluent,
    this.waterAt,
    this.waterByClock,
    this.waterByName,
    this.airMeter1,
    this.airMeter2,
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
  final DateTime? utilitiesAt;
  final String? utilitiesByClock;
  final String? utilitiesByName;

  // ── Fresh + effluent (one meter each) ────────────────────────────────────
  final double? freshWater;
  final double? effluent;
  final DateTime? waterAt;
  final String? waterByClock;
  final String? waterByName;

  // ── Air condenser ────────────────────────────────────────────────────────
  final double? airMeter1;
  final double? airMeter2;
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
      utilitiesAt: _ts(d['utilities_at']),
      utilitiesByClock: d['utilities_by_clock'] as String?,
      utilitiesByName: d['utilities_by_name'] as String?,
      freshWater: _num(d['fresh_water']),
      effluent: _num(d['effluent']),
      waterAt: _ts(d['water_at']),
      waterByClock: d['water_by_clock'] as String?,
      waterByName: d['water_by_name'] as String?,
      airMeter1: _num(d['air_meter_1']),
      airMeter2: _num(d['air_meter_2']),
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
      m['utilities_at'] = Timestamp.fromDate(now);
      m['utilities_by_clock'] = actorClockNo;
      m['utilities_by_name'] = actorName;
    }
    if (includeWater) {
      m['fresh_water'] = freshWater;
      m['effluent'] = effluent;
      m['water_at'] = Timestamp.fromDate(now);
      m['water_by_clock'] = actorClockNo;
      m['water_by_name'] = actorName;
    }
    if (includeAir) {
      m['air_meter_1'] = airMeter1;
      m['air_meter_2'] = airMeter2;
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
    return m;
  }

  LurgiDailyRound copyWith({
    double? gasMechanical,
    double? gasElectrical,
    double? boilerFeed,
    double? softener,
    double? freshWater,
    double? effluent,
    double? airMeter1,
    double? airMeter2,
    double? geyserTemp,
    String? geyserComments,
    double? tank1Litres,
    String? tank1Direction,
    double? tank2Litres,
    String? tank2Direction,
    double? tank3Litres,
    String? tank3Direction,
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
      utilitiesAt: utilitiesAt,
      utilitiesByClock: utilitiesByClock,
      utilitiesByName: utilitiesByName,
      freshWater: freshWater ?? this.freshWater,
      effluent: effluent ?? this.effluent,
      waterAt: waterAt,
      waterByClock: waterByClock,
      waterByName: waterByName,
      airMeter1: airMeter1 ?? this.airMeter1,
      airMeter2: airMeter2 ?? this.airMeter2,
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

/// Cumulative meter delta. Null previous → null delta (first capture).
/// [reset] treats [current] as the full post-reset usage.
double? lurgiMeterDelta(double? previous, double current, {bool reset = false}) {
  if (reset) return current;
  if (previous == null) return null;
  return current - previous;
}
