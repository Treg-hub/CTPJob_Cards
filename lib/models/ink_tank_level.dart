// Operational factory tank levels (ops estimate — not ledger WAC).
// Doc id = stock item code. Direct client set/increment; re-dip corrects drift.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/ink_toloul.dart';

/// Tanked ink-factory items (CoverWax has no tank).
const List<String> kInkTankItemCodes = [
  'yellow',
  'red',
  'blue',
  'black',
  'gravure_binder',
  kToloulItemCode,
];

/// Default low thresholds when a tank doc is first created.
const Map<String, double> kDefaultTankLowThresholds = {
  'yellow': 500,
  'red': 400,
  'blue': 400,
  'black': 400,
  'gravure_binder': 300,
  kToloulItemCode: kDefaultToloulFactoryLowLitres,
};

/// Placeholder capacities — operators replace with real tank sizes on tank screen.
const Map<String, double> kDefaultTankCapacities = {
  'yellow': 5000,
  'red': 5000,
  'blue': 5000,
  'black': 5000,
  'gravure_binder': 5000,
  kToloulItemCode: 20000,
};

const Map<String, String> kTankUnits = {
  'yellow': 'KG',
  'red': 'KG',
  'blue': 'KG',
  'black': 'KG',
  'gravure_binder': 'KG',
  kToloulItemCode: 'LTS',
};

const Map<String, String> kTankDisplayNames = {
  'yellow': 'Yellow',
  'red': 'Red',
  'blue': 'Blue',
  'black': 'Black',
  'gravure_binder': 'Binder',
  kToloulItemCode: 'Toloul',
};

bool isInkTankItem(String itemCode) => kInkTankItemCodes.contains(itemCode);

/// Live ops tank level for one factory tank.
class InkTankLevel {
  const InkTankLevel({
    required this.itemCode,
    required this.balance,
    required this.capacity,
    required this.lowThreshold,
    required this.unit,
    this.updatedAt,
    this.updatedByClockNo,
    this.updatedByName,
    this.lastDipAt,
    this.lastDipByClockNo,
    this.lastDipByName,
  });

  final String itemCode;
  final double balance;
  final double capacity;
  final double lowThreshold;
  final String unit;
  final DateTime? updatedAt;
  final String? updatedByClockNo;
  final String? updatedByName;
  final DateTime? lastDipAt;
  final String? lastDipByClockNo;
  final String? lastDipByName;

  String get displayName => kTankDisplayNames[itemCode] ?? itemCode;

  bool get isLow => balance < lowThreshold;

  /// Percent full 0–100, or null when capacity is unset/zero.
  double? get percentFull {
    if (capacity <= 0) return null;
    final pct = (balance / capacity) * 100;
    if (pct.isNaN || pct.isInfinite) return null;
    return pct.clamp(0, 100);
  }

  factory InkTankLevel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final code = doc.id;
    return InkTankLevel(
      itemCode: code,
      balance: (d['balance'] as num?)?.toDouble() ?? 0,
      capacity: (d['capacity'] as num?)?.toDouble() ??
          kDefaultTankCapacities[code] ??
          0,
      lowThreshold: (d['low_threshold'] as num?)?.toDouble() ??
          kDefaultTankLowThresholds[code] ??
          0,
      unit: d['unit'] as String? ?? kTankUnits[code] ?? 'KG',
      updatedAt: (d['updated_at'] as Timestamp?)?.toDate(),
      updatedByClockNo: d['updated_by_clock_no'] as String?,
      updatedByName: d['updated_by_name'] as String?,
      lastDipAt: (d['last_dip_at'] as Timestamp?)?.toDate(),
      lastDipByClockNo: d['last_dip_by_clock_no'] as String?,
      lastDipByName: d['last_dip_by_name'] as String?,
    );
  }

  /// Seed values when creating a missing doc on first increment.
  static Map<String, dynamic> seedFields(String itemCode) => {
        'balance': 0,
        'capacity': kDefaultTankCapacities[itemCode] ?? 0,
        'low_threshold': kDefaultTankLowThresholds[itemCode] ?? 0,
        'unit': kTankUnits[itemCode] ?? 'KG',
      };
}
