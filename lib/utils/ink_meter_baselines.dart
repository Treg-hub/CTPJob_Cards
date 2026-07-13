/// Pure helpers for daily-readings meter baselines.
///
/// Voided `consumption_meter` rows stay in Firestore for audit/replay, but they
/// must **not** contribute to "last reading" or recent history on the capture
/// screen — otherwise a void-and-re-enter on the same cumulative value yields
/// Δ = 0 and under-records the day.
library;

/// Newest non-voided cumulative meter value per key (item code or point id).
Map<String, double> latestNonVoidedMeterReadings(
  Iterable<({String key, DateTime at, double reading, bool voided})> rows,
) {
  final latest = <String, ({DateTime at, double reading})>{};
  for (final row in rows) {
    if (row.voided) continue;
    final cur = latest[row.key];
    if (cur == null || row.at.isAfter(cur.at)) {
      latest[row.key] = (at: row.at, reading: row.reading);
    }
  }
  return {for (final e in latest.entries) e.key: e.value.reading};
}

/// Newest-first non-voided readings per key, capped at [limit] each.
Map<String, List<({DateTime at, double reading})>> recentNonVoidedMeterReadings(
  Iterable<({String key, DateTime at, double reading, bool voided})> rows, {
  int limit = 4,
}) {
  final byKey = <String, List<({DateTime at, double reading})>>{};
  for (final row in rows) {
    if (row.voided) continue;
    (byKey[row.key] ??= []).add((at: row.at, reading: row.reading));
  }
  for (final key in byKey.keys.toList()) {
    final list = byKey[key]!..sort((a, b) => b.at.compareTo(a.at));
    if (list.length > limit) byKey[key] = list.sublist(0, limit);
  }
  return byKey;
}
