import 'package:cloud_firestore/cloud_firestore.dart';

/// One toloul recycling machine cycle (`lurgi_recycling_runs/{autoId}`).
/// Multiple runs per day when dirty toloul is available.
class LurgiRecyclingRun {
  const LurgiRecyclingRun({
    this.id,
    required this.dateKey,
    required this.startAt,
    required this.finishAt,
    required this.steamTemp,
    required this.steamPress,
    required this.litresRecycled,
    required this.dirtyToloulLevelLitres,
    required this.machineCleaned,
    required this.actorClockNo,
    required this.actorName,
    this.recordedAt,
    this.voided = false,
    this.voidRequested = false,
    this.voidRequestReason,
    this.voidRequestedAt,
    this.voidRequestedByClockNo,
    this.voidRequestedByName,
  });

  final String? id;
  final String dateKey;
  final DateTime startAt;
  final DateTime finishAt;
  final double steamTemp;
  final double steamPress;
  final double litresRecycled;
  final double dirtyToloulLevelLitres;
  final bool machineCleaned;
  final String actorClockNo;
  final String actorName;
  final DateTime? recordedAt;
  final bool voided;
  final bool voidRequested;
  final String? voidRequestReason;
  final DateTime? voidRequestedAt;
  final String? voidRequestedByClockNo;
  final String? voidRequestedByName;

  Duration get duration {
    final d = finishAt.difference(startAt);
    return d.isNegative ? Duration.zero : d;
  }

  factory LurgiRecyclingRun.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return LurgiRecyclingRun(
      id: doc.id,
      dateKey: d['date_key'] as String? ?? '',
      startAt: _ts(d['start_at']) ?? DateTime.now(),
      finishAt: _ts(d['finish_at']) ?? DateTime.now(),
      steamTemp: _num(d['steam_temp']) ?? 0,
      steamPress: _num(d['steam_press']) ?? 0,
      litresRecycled: _num(d['litres_recycled']) ?? 0,
      dirtyToloulLevelLitres: _num(d['dirty_toloul_level_litres']) ?? 0,
      machineCleaned: d['machine_cleaned'] as bool? ?? false,
      actorClockNo: d['actor_clock_no'] as String? ?? '',
      actorName: d['actor_name'] as String? ?? '',
      recordedAt: _ts(d['recorded_at']),
      voided: d['voided'] as bool? ?? false,
      voidRequested: d['void_requested'] as bool? ?? false,
      voidRequestReason: d['void_request_reason'] as String?,
      voidRequestedAt: _ts(d['void_requested_at']),
      voidRequestedByClockNo: d['void_requested_by_clock_no'] as String?,
      voidRequestedByName: d['void_requested_by_name'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'date_key': dateKey,
        'start_at': Timestamp.fromDate(startAt),
        'finish_at': Timestamp.fromDate(finishAt),
        'steam_temp': steamTemp,
        'steam_press': steamPress,
        'litres_recycled': litresRecycled,
        'dirty_toloul_level_litres': dirtyToloulLevelLitres,
        'machine_cleaned': machineCleaned,
        'actor_clock_no': actorClockNo,
        'actor_name': actorName,
        'recorded_at': FieldValue.serverTimestamp(),
      };

  static double? _num(dynamic v) => (v as num?)?.toDouble();

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

class LurgiRecyclingDaySummary {
  const LurgiRecyclingDaySummary({
    this.runCount = 0,
    this.totalLitresRecycled = 0,
    this.voidRequestedCount = 0,
  });

  final int runCount;
  final double totalLitresRecycled;
  final int voidRequestedCount;

  factory LurgiRecyclingDaySummary.fromRuns(List<LurgiRecyclingRun> runs) {
    var litres = 0.0;
    var pending = 0;
    for (final r in runs) {
      litres += r.litresRecycled;
      if (r.voidRequested) pending++;
    }
    return LurgiRecyclingDaySummary(
      runCount: runs.length,
      totalLitresRecycled: litres,
      voidRequestedCount: pending,
    );
  }
}
