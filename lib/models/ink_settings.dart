import 'package:cloud_firestore/cloud_firestore.dart';

/// Ink Factory module configuration (`ink_settings/config`).
///
/// `closedPeriods` implements the period-close lock: months listed here are
/// finalised, so backdating a transaction into them requires a manager override
/// and flags the month's report for re-issue via `periodsNeedingReissue`.
/// Open months backdate freely. Period keys are `YYYY-MM` (e.g. `2026-04`).
class InkSettings {
  const InkSettings({
    this.inkEnabled = true,
    this.closedPeriods = const [],
    this.periodsNeedingReissue = const [],
  });

  final bool inkEnabled;
  final List<String> closedPeriods;

  /// Closed periods where a manager-override transaction was recorded after
  /// finalisation — the report for these months must be re-issued.
  final List<String> periodsNeedingReissue;

  static const InkSettings defaults = InkSettings();

  /// Period key (`YYYY-MM`) for a given date.
  static String periodKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  bool isPeriodClosed(DateTime effectiveAt) =>
      closedPeriods.contains(periodKey(effectiveAt));

  bool isPeriodNeedingReissue(DateTime effectiveAt) =>
      periodsNeedingReissue.contains(periodKey(effectiveAt));

  factory InkSettings.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkSettings(
      inkEnabled: d['ink_enabled'] as bool? ?? true,
      closedPeriods: (d['closed_periods'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      periodsNeedingReissue:
          (d['periods_needing_reissue'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'ink_enabled': inkEnabled,
        'closed_periods': closedPeriods,
        'periods_needing_reissue': periodsNeedingReissue,
      };

  InkSettings copyWith({
    bool? inkEnabled,
    List<String>? closedPeriods,
    List<String>? periodsNeedingReissue,
  }) =>
      InkSettings(
        inkEnabled: inkEnabled ?? this.inkEnabled,
        closedPeriods: closedPeriods ?? this.closedPeriods,
        periodsNeedingReissue:
            periodsNeedingReissue ?? this.periodsNeedingReissue,
      );
}
