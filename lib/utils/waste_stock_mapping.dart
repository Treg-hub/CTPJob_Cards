import '../models/waste_stock_item.dart';
import '../models/waste_stock_source.dart';
import '../models/waste_type.dart';

/// Parent [waste_type] on legacy stock records for paper-family material.
const kPaperWasteStockParent = 'Paper Waste';

const kDefaultPaperStockSubtypes = {
  'Slab Waste',
  'Reelends',
  'Scrap Reels',
};

const kPaperFamilyNames = {
  kPaperWasteStockParent,
  'Slab Waste',
  'Reelends',
  'Scrap Reels',
  'Reels',
};

const kStockNameAliases = <String, List<String>>{
  'Scrap Reels': ['Scrap Reels', 'Reels'],
  'Reels': ['Scrap Reels', 'Reels'],
};

Set<String> flatWasteTypeNames(List<WasteType> allTypes) {
  return allTypes
      .map((t) => t.mainType)
      .where((name) => name.isNotEmpty && name != kPaperWasteStockParent)
      .toSet();
}

bool chipIsPaperFamily(String name) => kPaperFamilyNames.contains(name);

bool chipCanLinkStock(WasteType chip, List<WasteType> allTypes) {
  if (chip.mainType == kPaperWasteStockParent) return true;
  if (flatWasteTypeNames(allTypes).contains(chip.mainType)) return true;
  return kPaperFamilyNames.contains(chip.mainType);
}

Set<String> paperStockSubtypes(List<WasteType> allTypes) {
  final flatPaper = flatWasteTypeNames(allTypes)
      .where(chipIsPaperFamily)
      .toList();
  if (flatPaper.isNotEmpty) return flatPaper.toSet();
  return kDefaultPaperStockSubtypes;
}

bool chipMapsToPaperStock(WasteType chip, List<WasteType> allTypes) {
  return chipCanLinkStock(chip, allTypes);
}

bool selectedChipsUsePaperStock(
  List<WasteType> selected,
  List<WasteType> allTypes,
) {
  return selected.isNotEmpty &&
      selected.every((chip) => chipCanLinkStock(chip, allTypes));
}

String resolveLoadMainWasteType(
  List<WasteType> selected,
  List<WasteType> allTypes,
) {
  if (selected.isEmpty) return '';
  if (selected.every((chip) => chipIsPaperFamily(chip.mainType))) {
    return kPaperWasteStockParent;
  }
  return selected.first.mainType;
}

bool loadUsesPaperStock(String? mainWasteType, List<WasteType> allTypes) {
  if (mainWasteType == null || mainWasteType.isEmpty) return false;
  if (mainWasteType == kPaperWasteStockParent) return true;
  return chipIsPaperFamily(mainWasteType) ||
      flatWasteTypeNames(allTypes).contains(mainWasteType);
}

/// Copper stock is stored as waste_type "Copper Waste" + subtype Rods/Nuggets.
/// Loads may be labeled Copper Waste, Rods, Nuggets, or "Copper Nuggets".
const kCopperStockFamilyNames = {
  WasteStockTypes.copperWaste,
  WasteStockTypes.copperRods,
  WasteStockTypes.copperNuggets,
  'Copper Rods',
  'Copper Nuggets',
};

bool isCopperStockFamilyName(String? name) {
  if (name == null || name.isEmpty) return false;
  if (kCopperStockFamilyNames.contains(name)) return true;
  final lower = name.toLowerCase();
  return lower.contains('copper') &&
      (lower.contains('rod') ||
          lower.contains('nugget') ||
          lower == 'copper waste');
}

bool loadUsesCopperStock(String? mainWasteType) =>
    isCopperStockFamilyName(mainWasteType);

/// Subtype filter that matches staged copper waste_stock rows.
Set<String> copperStockSubtypeFilter() => {
      WasteStockTypes.copperWaste,
      WasteStockTypes.copperRods,
      WasteStockTypes.copperNuggets,
      'Copper Rods',
      'Copper Nuggets',
    };

bool stockItemIsCopper(WasteStockItem item) {
  if (item.source.isCopperSellStaging) return true;
  if (item.wasteType == WasteStockTypes.copperWaste) return true;
  return isCopperStockFamilyName(item.subtype) ||
      isCopperStockFamilyName(item.wasteType);
}

/// Loads that support linking on-site stock at collection (not only at schedule).
bool loadCanLinkOnSiteStock(String? mainWasteType, List<WasteType> allTypes) {
  if (mainWasteType == null || mainWasteType.isEmpty) return false;
  if (loadUsesPaperStock(mainWasteType, allTypes)) return true;
  if (mainWasteType == WasteStockTypes.ibcBins) return true;
  if (loadUsesCopperStock(mainWasteType)) return true;
  return flatWasteTypeNames(allTypes).contains(mainWasteType);
}

/// Restricts [contractorTypes] (the full set of waste types linked to the
/// load's contractor) down to the manager's [selectedWasteTypes] chosen at
/// scheduling time. Falls back to the unrestricted [contractorTypes] when
/// [selectedWasteTypes] is empty — covers legacy scheduled loads created
/// before this field existed, and any load with no scheduling step at all.
///
/// Used by WasteBeginCollectionScreen so the guard's item/stock pickers only
/// offer what the manager actually planned for, with an admin-only override
/// available to widen back to [contractorTypes] (see _adminOverrideActive).
List<WasteType> restrictToScheduledTypes(
  List<WasteType> contractorTypes,
  List<String> selectedWasteTypes,
) {
  if (selectedWasteTypes.isEmpty) return contractorTypes;
  final allowed = selectedWasteTypes.toSet();
  return contractorTypes
      .where((t) => allowed.contains(t.mainType))
      .toList();
}

String stockLinkParentType(String? mainWasteType) {
  if (mainWasteType == null || mainWasteType.isEmpty) {
    return kPaperWasteStockParent;
  }
  if (loadUsesCopperStock(mainWasteType)) {
    return WasteStockTypes.copperWaste;
  }
  if (mainWasteType == kPaperWasteStockParent ||
      mainWasteType == WasteStockTypes.ibcBins) {
    return mainWasteType;
  }
  return mainWasteType;
}

/// Filter for [WasteStockLinkSheet] from a load's main type (collection / schedule).
Set<String>? stockSubtypeFilterForLoadMainType(
  String? mainWasteType,
  List<WasteType> allTypes,
) {
  if (mainWasteType == null || mainWasteType.isEmpty) return null;
  if (loadUsesCopperStock(mainWasteType)) {
    return copperStockSubtypeFilter();
  }
  if (mainWasteType == kPaperWasteStockParent) return null;
  if (loadUsesPaperStock(mainWasteType, allTypes)) {
    return {mainWasteType};
  }
  if (mainWasteType == WasteStockTypes.ibcBins) {
    return {WasteStockTypes.ibcBins};
  }
  return {mainWasteType};
}

Set<String> expandStockFilter(Iterable<String> names) {
  final filter = <String>{};
  for (final name in names) {
    filter.add(name);
    for (final alias in kStockNameAliases[name] ?? const []) {
      filter.add(alias);
    }
  }
  return filter;
}

List<String> itemSubtypeOptionsForChips(
  List<WasteType> selectedChips,
  List<WasteType> allTypes,
) {
  if (selectedChips.isEmpty) return const [];

  final onlyPaperChip = selectedChips.length == 1 &&
      selectedChips.first.mainType == kPaperWasteStockParent;
  if (onlyPaperChip) {
    return paperStockSubtypes(allTypes).toList()..sort();
  }

  return selectedChips.map((c) => c.mainType).toList()..sort();
}

Set<String> stockSubtypeFilterForChips(
  List<WasteType> selectedChips,
  List<WasteType> allTypes,
) {
  if (selectedChips.isEmpty) return {};

  if (selectedChips.any((c) => loadUsesCopperStock(c.mainType))) {
    return copperStockSubtypeFilter();
  }

  final onlyPaperChip = selectedChips.length == 1 &&
      selectedChips.first.mainType == kPaperWasteStockParent;
  if (onlyPaperChip) return paperStockSubtypes(allTypes);

  return expandStockFilter(selectedChips.map((c) => c.mainType));
}

bool stockItemMatchesFilter(WasteStockItem item, Set<String> filter) {
  if (filter.isEmpty) return true;

  // Copper: load may say "Copper Nuggets" while stock is waste_type Copper Waste
  // + subtype Nuggets / Rods (continuous sell pools).
  final filterCopper = filter.any(isCopperStockFamilyName);
  if (filterCopper && stockItemIsCopper(item)) {
    final wantsRods = filter.any((f) {
      final l = f.toLowerCase();
      return l == 'rods' || l.contains('rod');
    });
    final wantsNuggets = filter.any((f) {
      final l = f.toLowerCase();
      return l == 'nuggets' || l.contains('nugget');
    });
    final wantsAllCopper = filter.contains(WasteStockTypes.copperWaste) ||
        (!wantsRods && !wantsNuggets);
    if (wantsAllCopper) return true;
    final st = item.subtype.toLowerCase();
    if (wantsRods && (st == 'rods' || st.contains('rod'))) return true;
    if (wantsNuggets && (st == 'nuggets' || st.contains('nugget'))) return true;
    return false;
  }

  final subtype = item.subtype.isNotEmpty ? item.subtype : item.wasteType;
  if (filter.contains(subtype) || filter.contains(item.wasteType)) {
    return true;
  }
  for (final name in filter) {
    for (final alias in kStockNameAliases[name] ?? const []) {
      if (alias == subtype || alias == item.wasteType) return true;
    }
  }
  return false;
}

List<WasteStockItem> filterStockByChipSubtypes(
  List<WasteStockItem> stock,
  List<WasteType> selectedChips,
  List<WasteType> allTypes,
) {
  if (selectedChips.isEmpty) return const [];

  final filter = stockSubtypeFilterForChips(selectedChips, allTypes);
  final onlyPaperChip = selectedChips.length == 1 &&
      selectedChips.first.mainType == kPaperWasteStockParent;
  if (onlyPaperChip) {
    return stock.where((item) => stockItemMatchesFilter(item, filter)).toList();
  }

  return stock
      .where((item) => stockItemMatchesFilter(item, filter))
      .toList();
}