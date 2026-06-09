import '../models/waste_stock_item.dart';
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

  final onlyPaperChip = selectedChips.length == 1 &&
      selectedChips.first.mainType == kPaperWasteStockParent;
  if (onlyPaperChip) return paperStockSubtypes(allTypes);

  return expandStockFilter(selectedChips.map((c) => c.mainType));
}

bool stockItemMatchesFilter(WasteStockItem item, Set<String> filter) {
  if (filter.isEmpty) return true;
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