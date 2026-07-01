/// Provenance for auto-created or manual on-site waste stock.
enum WasteStockSource {
  manual('manual'),
  inkConsume('ink_consume'),
  /// Consolidated IBC pool doc accumulated across multiple ink IBC consumes
  /// (and any split-off doc derived from one) — see waste_stock_crosslink.dart.
  inkConsumePool('ink_consume_pool'),
  copperThreshold('copper_threshold');

  const WasteStockSource(this.value);
  final String value;

  static WasteStockSource fromString(String? raw) {
    switch (raw) {
      case 'ink_consume':
        return WasteStockSource.inkConsume;
      case 'ink_consume_pool':
        return WasteStockSource.inkConsumePool;
      case 'copper_threshold':
        return WasteStockSource.copperThreshold;
      default:
        return WasteStockSource.manual;
    }
  }
}

/// Who may browse this stock item in inventory views (collection picker may differ).
enum WasteStockVisibility {
  all('all'),
  managerOnly('manager_only');

  const WasteStockVisibility(this.value);
  final String value;

  static WasteStockVisibility fromString(String? raw) {
    return raw == 'manager_only'
        ? WasteStockVisibility.managerOnly
        : WasteStockVisibility.all;
  }
}

/// Cross-module waste stock type labels (must match waste_types seeds).
abstract final class WasteStockTypes {
  static const String ibcBins = 'IBC Bins';
  static const String copperWaste = 'Copper Waste';
  static const String copperRods = 'Rods';
  static const String copperNuggets = 'Nuggets';
}

/// Minimum sell bucket total before copper auto-creates waste_stock.
const double kCopperWasteStockThresholdKg = 400.0;

/// Doc id (within `Collections.wasteStockPoolPointers`) for the deterministic
/// "current open IBC pool" lookup used by [WasteStockCrosslink] — a
/// transactional read of this single known doc is what makes
/// find-or-create-the-pool safe under concurrent writers (a transactional
/// *query* for "does a pool exist" would not serialize against a concurrent
/// transaction doing the same query).
const String kIbcPoolPointerDocId = 'ibc_bins';