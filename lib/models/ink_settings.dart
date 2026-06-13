import 'package:cloud_firestore/cloud_firestore.dart';

/// Ink Factory module configuration (`ink_settings/config`).
///
/// `closedPeriods` implements the period-close lock (option B): months listed
/// here are finalised, so backdating a transaction into them requires a manager
/// override and flags the month's report for re-issue. Open months backdate
/// freely. Period keys are `YYYY-MM` (e.g. `2026-04`).
class InkSettings {
  const InkSettings({
    this.inkEnabled = true,
    this.closedPeriods = const [],
  });

  final bool inkEnabled;
  final List<String> closedPeriods;

  static const InkSettings defaults = InkSettings();

  /// Period key (`YYYY-MM`) for a given date.
  static String periodKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  bool isPeriodClosed(DateTime effectiveAt) =>
      closedPeriods.contains(periodKey(effectiveAt));

  factory InkSettings.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkSettings(
      inkEnabled: d['ink_enabled'] as bool? ?? true,
      closedPeriods: (d['closed_periods'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'ink_enabled': inkEnabled,
        'closed_periods': closedPeriods,
      };

  InkSettings copyWith({bool? inkEnabled, List<String>? closedPeriods}) =>
      InkSettings(
        inkEnabled: inkEnabled ?? this.inkEnabled,
        closedPeriods: closedPeriods ?? this.closedPeriods,
      );
}
