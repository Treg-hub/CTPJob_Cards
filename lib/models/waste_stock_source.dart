/// Provenance for auto-created or manual on-site waste stock.
enum WasteStockSource {
  manual('manual'),
  inkConsume('ink_consume'),
  /// Consolidated IBC pool doc accumulated across multiple ink IBC consumes
  /// (and any split-off doc derived from one) — see waste_stock_crosslink.dart.
  inkConsumePool('ink_consume_pool'),
  /// Legacy: created at old 400 kg threshold. Treated like [copperSell] for link/deduct.
  copperThreshold('copper_threshold'),
  /// Continuous stage: plate bars / sort-to-sell → on-site copper waste stock pools.
  copperSell('copper_sell');

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
      case 'copper_sell':
        return WasteStockSource.copperSell;
      default:
        return WasteStockSource.manual;
    }
  }

  /// Copper staged for collection (continuous sell pools or legacy threshold).
  bool get isCopperSellStaging =>
      this == WasteStockSource.copperSell ||
      this == WasteStockSource.copperThreshold;
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

/// Doc id (within `Collections.wasteStockPoolPointers`) for the deterministic
/// "current open IBC pool" lookup used by [WasteStockCrosslink].
const String kIbcPoolPointerDocId = 'ibc_bins';

/// Open copper rods sell pool pointer (`waste_stock_pool_pointers/copper_rods`).
const String kCopperRodsPoolPointerDocId = 'copper_rods';

/// Open copper nuggets sell pool pointer (`waste_stock_pool_pointers/copper_nuggets`).
const String kCopperNuggetsPoolPointerDocId = 'copper_nuggets';
