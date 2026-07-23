/// Shared fleet module constants.
const int kFleetMaxPhotos = 10;

/// Curated Hyster / forklift parts for Mark Fixed & Log work quick picks.
/// Shown before names learned from past `fleet_work_parts` (case-insensitive merge).
const List<String> kFleetCommonPartNames = [
  'Hydraulic hose',
  'Hydraulic seal kit',
  'Hydraulic oil',
  'Oil filter',
  'Air filter',
  'Fuel filter',
  'Drive tyre',
  'Steer tyre',
  'Fork tip',
  'Lift chain',
  'Mast roller',
  'Brake pads',
  'Seat switch',
  'Horn',
  'Fuse',
  'Relay',
  'Battery connector',
  'LPG regulator',
  'Coolant',
  'Fan belt',
];

/// Common picks first (stable order), then historical names A–Z. Dedupes by
/// lower-case so past jobs do not duplicate a curated label.
List<String> mergeFleetPartSuggestions(Iterable<String> historical) {
  final seen = <String>{};
  final out = <String>[];

  void add(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    final key = name.toLowerCase();
    if (seen.contains(key)) return;
    seen.add(key);
    out.add(name);
  }

  for (final name in kFleetCommonPartNames) {
    add(name);
  }

  final sortedHist = historical
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  for (final name in sortedHist) {
    add(name);
  }

  return out;
}
