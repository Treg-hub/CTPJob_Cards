/// Provenance for auto-created or manual on-site waste stock.
enum WasteStockSource {
  manual('manual'),
  inkConsume('ink_consume'),
  copperThreshold('copper_threshold');

  const WasteStockSource(this.value);
  final String value;

  static WasteStockSource fromString(String? raw) {
    switch (raw) {
      case 'ink_consume':
        return WasteStockSource.inkConsume;
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