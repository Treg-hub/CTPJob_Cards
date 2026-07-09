import '../models/waste_item.dart';
import '../models/waste_stock_source.dart';
import '../models/waste_type.dart';

/// Routing and measurement rules for waste types.
///
/// Two special flags on [WasteType] drive the load lifecycle:
/// - [WasteType.isQuantityOnly]: priced per unit; weighbridge is skipped entirely.
/// - [WasteType.noSiteWeight]: guard records quantity only; certified weight
///   arrives later at the off-site weighbridge.
WasteType? findWasteTypeByName(String? name, List<WasteType> allTypes) {
  if (name == null || name.isEmpty) return null;
  for (final t in allTypes) {
    if (t.mainType == name) return t;
    if (t.subtypes.contains(name)) return t;
  }
  return null;
}

bool typeSkipsWeighbridge(WasteType type) => type.isQuantityOnly;

bool typeHasNoSiteWeight(WasteType type) => type.noSiteWeight;

/// True when the load's main type is quantity-only (e.g. IBC Bins).
bool mainTypeSkipsWeighbridge(String mainWasteType, List<WasteType> allTypes) {
  final type = findWasteTypeByName(mainWasteType, allTypes);
  return type?.isQuantityOnly ?? false;
}

/// True when every collected item is quantity-only (mixed-load edge case).
bool itemsAllQuantityOnly(Iterable<bool> itemQuantityOnlyFlags) {
  final list = itemQuantityOnlyFlags.toList();
  return list.isNotEmpty && list.every((v) => v);
}

/// Whether this load should skip the weighbridge step after collection/finish.
bool loadSkipsWeighbridge({
  required String mainWasteType,
  required List<WasteType> allTypes,
  Iterable<bool> itemQuantityOnlyFlags = const [],
}) {
  if (mainTypeSkipsWeighbridge(mainWasteType, allTypes)) return true;
  return itemsAllQuantityOnly(itemQuantityOnlyFlags);
}

/// Sum on-site recorded weight for deviation checks.
/// Quantity-only and no-site-weight items contribute 0 at collection time.
double sumRecordedWeightKg(Iterable<Map<String, dynamic>> itemsData) {
  var total = 0.0;
  for (final item in itemsData) {
    if (item['is_quantity_only'] == true) continue;
    if (item['is_no_site_weight'] == true) continue;
    total += (item['weight_kg'] as num?)?.toDouble() ?? 0.0;
  }
  return total;
}

double sumRecordedWeightFromItems(Iterable<WasteItem> items) {
  var total = 0.0;
  for (final item in items) {
    if (item.isQuantityOnly || item.isNoSiteWeight) continue;
    total += item.weightKg;
  }
  return total;
}

/// Line value for cost review — quantity × rate or weight × rate.
double itemLineValue(WasteItem item, double ratePerUnit) {
  if (ratePerUnit <= 0) return 0;
  if (item.isQuantityOnly) return (item.quantity ?? 0) * ratePerUnit;
  return item.weightKg * ratePerUnit;
}

String itemMeasureLabel(WasteItem item) {
  if (item.isQuantityOnly || item.isNoSiteWeight) {
    return '${item.quantity ?? 0} units';
  }
  return '${item.weightKg.toStringAsFixed(1)} kg';
}

String itemRateColumnLabel(WasteItem item) {
  return item.isQuantityOnly ? 'R/unit' : 'R/kg';
}

/// On-site stock uses subtype/waste_type names — align with Pulse waste_types.
bool stockTypeIsQuantityOnly(String typeName, List<WasteType> allTypes) {
  final type = findWasteTypeByName(typeName, allTypes);
  if (type != null) return type.isQuantityOnly;
  return typeName == WasteStockTypes.ibcBins;
}

String stockQuantityLabelFor(String typeName, List<WasteType> allTypes) {
  final type = findWasteTypeByName(typeName, allTypes);
  if (type == null) {
    return typeName == WasteStockTypes.ibcBins ? 'Quantity (bins)' : 'Quantity';
  }
  return type.quantityLabelFor(typeName);
}
