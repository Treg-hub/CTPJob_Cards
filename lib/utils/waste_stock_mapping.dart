import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';

/// Parent [waste_type] field on stock records for paper subtypes.
const kPaperWasteStockParent = 'Paper Waste';

/// Fallback when the Paper Waste type record has no subtypes configured.
const kDefaultPaperStockSubtypes = {
  'Slab Waste',
  'Reelends',
  'Scrap Reels',
};

Set<String> paperStockSubtypes(List<WasteType> allTypes) {
  for (final type in allTypes) {
    if (type.mainType == kPaperWasteStockParent && type.subtypes.isNotEmpty) {
      return type.subtypes.toSet();
    }
  }
  return kDefaultPaperStockSubtypes;
}

bool chipMapsToPaperStock(WasteType chip, List<WasteType> allTypes) {
  if (chip.mainType == kPaperWasteStockParent) return true;
  return paperStockSubtypes(allTypes).contains(chip.mainType);
}

bool selectedChipsUsePaperStock(
  List<WasteType> selected,
  List<WasteType> allTypes,
) {
  return selected.isNotEmpty &&
      selected.every((chip) => chipMapsToPaperStock(chip, allTypes));
}

/// Resolves the load's [main_waste_type] from selected contractor chips.
String resolveLoadMainWasteType(
  List<WasteType> selected,
  List<WasteType> allTypes,
) {
  if (selected.isEmpty) return '';
  if (selectedChipsUsePaperStock(selected, allTypes)) {
    return kPaperWasteStockParent;
  }
  return selected.first.mainType;
}

bool loadUsesPaperStock(String? mainWasteType, List<WasteType> allTypes) {
  if (mainWasteType == null || mainWasteType.isEmpty) return false;
  if (mainWasteType == kPaperWasteStockParent) return true;
  return paperStockSubtypes(allTypes).contains(mainWasteType);
}

/// Subtype names allowed for fresh items / stock pickers based on selected chips.
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
  return itemSubtypeOptionsForChips(selectedChips, allTypes).toSet();
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
  if (onlyPaperChip) return stock;

  return stock.where((item) => filter.contains(item.subtype)).toList();
}