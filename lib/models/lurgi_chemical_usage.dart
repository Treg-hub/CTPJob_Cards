import 'package:cloud_firestore/cloud_firestore.dart';

/// One effluent-chemical dose entry (`lurgi_chemical_usage/{autoId}`).
/// Multiple entries per day; day totals = sum of kg fields.
class LurgiChemicalUsage {
  const LurgiChemicalUsage({
    this.id,
    required this.dateKey,
    required this.recordedAt,
    this.causticSodaKg = 0,
    this.hydrochloricAcidKg = 0,
    this.sodiumChlorideKg = 0,
    this.naccolaintKg = 0,
    this.comments,
    required this.actorClockNo,
    required this.actorName,
    this.voided = false,
  });

  final String? id;
  final String dateKey;
  final DateTime recordedAt;
  final double causticSodaKg;
  final double hydrochloricAcidKg;
  final double sodiumChlorideKg;
  final double naccolaintKg;
  final String? comments;
  final String actorClockNo;
  final String actorName;
  final bool voided;

  double get totalKg =>
      causticSodaKg +
      hydrochloricAcidKg +
      sodiumChlorideKg +
      naccolaintKg;

  factory LurgiChemicalUsage.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return LurgiChemicalUsage(
      id: doc.id,
      dateKey: d['date_key'] as String? ?? '',
      recordedAt: _ts(d['recorded_at']) ?? DateTime.now(),
      causticSodaKg: _num(d['caustic_soda_kg']) ?? 0,
      hydrochloricAcidKg: _num(d['hydrochloric_acid_kg']) ?? 0,
      sodiumChlorideKg: _num(d['sodium_chloride_kg']) ?? 0,
      naccolaintKg: _num(d['naccolaint_kg']) ?? 0,
      comments: d['comments'] as String?,
      actorClockNo: d['actor_clock_no'] as String? ?? '',
      actorName: d['actor_name'] as String? ?? '',
      voided: d['voided'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'date_key': dateKey,
        'recorded_at': Timestamp.fromDate(recordedAt),
        'caustic_soda_kg': causticSodaKg,
        'hydrochloric_acid_kg': hydrochloricAcidKg,
        'sodium_chloride_kg': sodiumChlorideKg,
        'naccolaint_kg': naccolaintKg,
        if (comments != null && comments!.trim().isNotEmpty)
          'comments': comments!.trim(),
        'actor_clock_no': actorClockNo,
        'actor_name': actorName,
      };

  static double? _num(dynamic v) => (v as num?)?.toDouble();

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

/// Day rollup for hub badges and totals strip.
class LurgiChemicalDayTotals {
  const LurgiChemicalDayTotals({
    this.entryCount = 0,
    this.causticSodaKg = 0,
    this.hydrochloricAcidKg = 0,
    this.sodiumChlorideKg = 0,
    this.naccolaintKg = 0,
  });

  final int entryCount;
  final double causticSodaKg;
  final double hydrochloricAcidKg;
  final double sodiumChlorideKg;
  final double naccolaintKg;

  double get totalKg =>
      causticSodaKg +
      hydrochloricAcidKg +
      sodiumChlorideKg +
      naccolaintKg;

  factory LurgiChemicalDayTotals.fromEntries(
      List<LurgiChemicalUsage> entries) {
    var c = 0.0, h = 0.0, s = 0.0, n = 0.0;
    for (final e in entries) {
      c += e.causticSodaKg;
      h += e.hydrochloricAcidKg;
      s += e.sodiumChlorideKg;
      n += e.naccolaintKg;
    }
    return LurgiChemicalDayTotals(
      entryCount: entries.length,
      causticSodaKg: c,
      hydrochloricAcidKg: h,
      sodiumChlorideKg: s,
      naccolaintKg: n,
    );
  }
}
