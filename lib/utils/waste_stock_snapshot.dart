import '../models/waste_stock_item.dart';

/// Serializable on-site stock row for offline create-load queuing.
abstract final class WasteStockSnapshot {
  static Map<String, dynamic> fromItem(WasteStockItem stock) {
    return {
      'id': stock.id,
      'waste_type': stock.wasteType,
      'subtype': stock.subtype,
      'photos': List<String>.from(stock.photos),
      if (stock.estimatedWeightKg != null)
        'estimated_weight_kg': stock.estimatedWeightKg,
      'quantity': stock.quantity,
      if (stock.notes != null && stock.notes!.isNotEmpty) 'notes': stock.notes,
      'status': stock.status.value,
      'is_deleted': stock.isDeleted,
    };
  }

  static List<Map<String, dynamic>> eligibleForQueue(
    List<String> selectedIds,
    List<Map<String, dynamic>> snapshots,
  ) {
    if (selectedIds.isEmpty || snapshots.isEmpty) return const [];
    final byId = <String, Map<String, dynamic>>{};
    for (final snap in snapshots) {
      final id = snap['id'] as String?;
      if (id != null && id.isNotEmpty) byId[id] = snap;
    }
    final eligible = <Map<String, dynamic>>[];
    for (final id in selectedIds) {
      final snap = byId[id];
      if (snap == null) continue;
      if (snap['is_deleted'] == true) continue;
      if (snap['status'] != WasteStockStatus.onSite.value) continue;
      eligible.add(snap);
    }
    return eligible;
  }

  static String label(Map<String, dynamic> snap) {
    final subtype = snap['subtype'] as String? ?? '';
    if (subtype.isNotEmpty) return subtype;
    return snap['waste_type'] as String? ?? '';
  }

  static double weightKg(Map<String, dynamic> snap) {
    return (snap['estimated_weight_kg'] as num?)?.toDouble() ?? 0;
  }

  static int quantity(Map<String, dynamic> snap) {
    return (snap['quantity'] as num?)?.toInt() ?? 0;
  }

  static List<String> photos(Map<String, dynamic> snap) {
    return List<String>.from(snap['photos'] as List? ?? const []);
  }
}