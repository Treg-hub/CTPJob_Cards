import '../models/job_card.dart';

/// Curated failure-subtype seeds for complete / monitor (and optional enrich).
///
/// **Breakdown family SSoT remains [JobType] (`type` field).** These strings are
/// free-text refinements under that type — techs may type new values; past
/// values + these seeds appear as suggestions (same idea as part autocomplete).
///
/// Seeded from Pressroom job-card patterns (2026-07 AI Intelligence export).
class FailureSubtypes {
  FailureSubtypes._();

  /// Suggested subtypes for the given breakdown family [type].
  static List<String> suggestionsFor(JobType type) {
    switch (type) {
      case JobType.mechanical:
        return List<String>.from(_mechanical);
      case JobType.electrical:
        return List<String>.from(_electrical);
      case JobType.mechanicalElectrical:
        return List<String>.from(_mechElec);
      case JobType.maintenance:
        return List<String>.from(_maintenance);
      case JobType.building:
        return List<String>.from(_building);
      case JobType.specialist:
      case JobType.postPressSpecialist:
        return List<String>.from(_specialist);
    }
  }

  /// Merge seeds with previously used free-text values (case-insensitive dedupe).
  static List<String> suggestionsWithHistory(
    JobType type,
    Iterable<String> previousUsed,
  ) {
    final seen = <String>{};
    final out = <String>[];
    void add(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(t);
    }

    for (final s in suggestionsFor(type)) {
      add(s);
    }
    for (final s in previousUsed) {
      add(s);
    }
    return out;
  }

  // --- Seeds by type (from Pressroom volume patterns) ---

  static const _mechanical = [
    'Pneumatic / air',
    'Mechanical wear / drive',
    'Hydraulic / oil',
    'Safety / access',
    'Process / quality',
    'Setup / adjust',
    'Bearings / rollers',
    'Folder / nips',
    'Other',
  ];

  static const _electrical = [
    'Sensors / switches / limits',
    'Power / supply / batteries',
    'Drives / motors / DC bus',
    'Controls / PLC / reset',
    'Wiring / connections',
    'Setup / calibrate',
    'Other',
  ];

  static const _mechElec = [
    'Cylinder load / arms',
    'Sensors & mechanics',
    'Interlock / safety',
    'Setup / calibrate',
    'Other',
  ];

  static const _maintenance = [
    'Planned service',
    'Inspection',
    'Lubrication / greasing',
    'Preventive check',
    'Other',
  ];

  static const _building = [
    'Floor / structure',
    'Doors / latches',
    'Access / safety',
    'Other',
  ];

  static const _specialist = [
    'Process / quality',
    'Mechanical',
    'Electrical',
    'Setup / adjust',
    'Other',
  ];
}
