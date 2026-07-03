import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/ink_toloul.dart';

/// Classifies a stock item, which drives report grouping and which flows can
/// touch it. Items are DATA-DRIVEN (`ink_stock_items` collection) — new items
/// are added without code changes; this enum only labels their behaviour.
enum InkItemClass {
  /// Bought, consumed as a production input (ASP 600, Spray105, Resink, …).
  raw('raw'),

  /// Toloul — bought + recovered; consumed in production and IBC washing.
  solvent('solvent'),

  /// Finished ink bought in IBCs (Yellow/Red/Blue/Black); leaves only via meter.
  ink('ink'),

  /// Produced in-house (CoverWax, Gravure Binder).
  manufactured('manufactured');

  const InkItemClass(this.value);
  final String value;

  static InkItemClass fromValue(String? value) => InkItemClass.values.firstWhere(
        (c) => c.value == value,
        orElse: () => InkItemClass.raw,
      );
}

/// A stock item and its current position. `currentBalance` / `weightedAverageCost`
/// are a CACHE of the append-only ledger (`ink_transactions`) — they are written
/// only by the server-authoritative write path, never edited directly by clients.
/// The document id is the [itemCode].
class InkStockItem {
  const InkStockItem({
    required this.itemCode,
    required this.displayName,
    required this.unit,
    required this.itemClass,
    required this.currentBalance,
    required this.weightedAverageCost,
    required this.lastUpdated,
    this.lastTransactionId,
    this.active = true,
    this.displayOrder = 9999,
    this.category = '',
    this.metered = false,
    this.factoryTankBalance,
    this.lurgiBalance,
  });

  final String itemCode;
  final String displayName;

  /// Each item lives in exactly one unit: 'KG' or 'LTS'.
  final String unit;
  final InkItemClass itemClass;

  /// Fixed display order (the legacy ITEMID) — all item lists sort by this, not
  /// alphabetically.
  final int displayOrder;

  /// Domain category label (Additive / Toloul / Ink / Binder) for display.
  final String category;

  /// Whether consumption is read off a meter (the 4 inks + gravure binder).
  /// CoverWax is produced and consumed into binder, but is NOT metered.
  final bool metered;

  /// Cached closing balance from the ledger (consolidated factory + Lurgi).
  final double currentBalance;

  /// Ink-factory tank only — operational balance for production/IBC (toloul).
  final double? factoryTankBalance;

  /// Lurgi-held toloul from the latest month-end split count (static mid-month).
  final double? lurgiBalance;

  /// Cached weighted-average cost from the ledger.
  final double weightedAverageCost;

  bool get isToloul => itemCode == kToloulItemCode;

  /// Balance available for ink-factory operations (falls back to consolidated).
  double get operationalBalance => factoryTankBalance ?? currentBalance;
  final DateTime lastUpdated;
  final String? lastTransactionId;
  final bool active;

  /// Current stock value (balance × WAC).
  double get value => currentBalance * weightedAverageCost;

  factory InkStockItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkStockItem(
      itemCode: doc.id,
      displayName: d['display_name'] as String? ?? doc.id,
      unit: d['unit'] as String? ?? 'KG',
      itemClass: InkItemClass.fromValue(d['item_class'] as String?),
      currentBalance: (d['current_balance'] as num?)?.toDouble() ?? 0,
      factoryTankBalance: (d['factory_tank_balance'] as num?)?.toDouble(),
      lurgiBalance: (d['lurgi_balance'] as num?)?.toDouble(),
      weightedAverageCost: (d['weighted_average_cost'] as num?)?.toDouble() ?? 0,
      lastUpdated:
          (d['last_updated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastTransactionId: d['last_transaction_id'] as String?,
      active: d['active'] as bool? ?? true,
      displayOrder: (d['display_order'] as num?)?.toInt() ?? 9999,
      category: d['category'] as String? ?? '',
      metered: d['metered'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'display_name': displayName,
        'unit': unit,
        'item_class': itemClass.value,
        'current_balance': currentBalance,
        'weighted_average_cost': weightedAverageCost,
        'last_updated': Timestamp.fromDate(lastUpdated),
        if (lastTransactionId != null) 'last_transaction_id': lastTransactionId,
        'active': active,
        'display_order': displayOrder,
        'category': category,
        'metered': metered,
      };

  InkStockItem copyWith({
    String? displayName,
    String? unit,
    InkItemClass? itemClass,
    double? currentBalance,
    double? weightedAverageCost,
    DateTime? lastUpdated,
    String? lastTransactionId,
    bool? active,
  }) =>
      InkStockItem(
        itemCode: itemCode,
        displayName: displayName ?? this.displayName,
        unit: unit ?? this.unit,
        itemClass: itemClass ?? this.itemClass,
        currentBalance: currentBalance ?? this.currentBalance,
        weightedAverageCost: weightedAverageCost ?? this.weightedAverageCost,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        lastTransactionId: lastTransactionId ?? this.lastTransactionId,
        active: active ?? this.active,
      );
}
