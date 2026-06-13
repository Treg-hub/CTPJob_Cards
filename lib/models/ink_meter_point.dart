import 'package:cloud_firestore/cloud_firestore.dart';

/// An auxiliary toloul meter point (`ink_meter_points`). These track where
/// toloul went (per lurgi / press) for reporting only — they have NO effect on
/// stock. Each point is linked to a group; month-end sums each group:
///   - `recovery` → Total Toloul Recovery (recovered for the Lurgi department)
///   - `usage`    → Total Toloul Usage (consumed at the presses)
/// Readings are cumulative (delta = consumption, with meter-reset handling),
/// stored in `ink_meter_point_readings`.
class InkMeterPoint {
  const InkMeterPoint({
    this.id,
    required this.name,
    required this.linkage,
    this.active = true,
    this.sortOrder = 0,
  });

  final String? id;
  final String name;
  final String linkage; // 'recovery' | 'usage'
  final bool active;
  final int sortOrder;

  static String linkageLabel(String linkage) => switch (linkage) {
        'recovery' => 'Toloul Recovery',
        'usage' => 'Toloul Usage',
        _ => linkage,
      };

  String get linkageLabelText => linkageLabel(linkage);

  factory InkMeterPoint.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkMeterPoint(
      id: doc.id,
      name: d['name'] as String? ?? '',
      linkage: d['linkage'] as String? ?? 'usage',
      active: d['active'] as bool? ?? true,
      sortOrder: (d['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'linkage': linkage,
        'active': active,
        'sort_order': sortOrder,
      };
}
