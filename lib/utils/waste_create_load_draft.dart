import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/waste_item.dart';

/// Local draft persistence for the guard "New Waste Load" form.
abstract final class WasteCreateLoadDraft {
  static String prefsKey(String? clockNo) =>
      'wasteCreateLoadDraft_${clockNo ?? 'unknown'}';

  static bool hasContent({
    required String driverName,
    required String vehicleReg,
    String? trailerReg,
    String? paperDocumentRef,
    String? notes,
    String? contractorId,
    List<String> selectedTypeIds = const [],
    List<WasteItem> items = const [],
    List<String> selectedStockIds = const [],
  }) {
    return driverName.trim().isNotEmpty ||
        vehicleReg.trim().isNotEmpty ||
        (trailerReg ?? '').trim().isNotEmpty ||
        (paperDocumentRef ?? '').trim().isNotEmpty ||
        (notes ?? '').trim().isNotEmpty ||
        contractorId != null ||
        selectedTypeIds.isNotEmpty ||
        items.isNotEmpty ||
        selectedStockIds.isNotEmpty;
  }

  static Map<String, dynamic> toJson({
    required String createSubmitRef,
    required String driverName,
    required String vehicleReg,
    String? trailerReg,
    String? paperDocumentRef,
    String? notes,
    String? contractorId,
    required List<String> selectedTypeIds,
    required String timeIn,
    String? timeOut,
    required List<WasteItem> items,
    required List<String> selectedStockIds,
    List<Map<String, dynamic>> selectedStockSnapshots = const [],
  }) {
    return {
      'create_submit_ref': createSubmitRef,
      'driver_name': driverName,
      'vehicle_reg': vehicleReg,
      'trailer_reg': trailerReg,
      'paper_document_ref': paperDocumentRef,
      'notes': notes,
      'contractor_id': contractorId,
      'selected_type_ids': selectedTypeIds,
      'time_in': timeIn,
      'time_out': timeOut,
      'selected_stock_ids': selectedStockIds,
      if (selectedStockSnapshots.isNotEmpty)
        'selected_stock_snapshots': selectedStockSnapshots,
      'items': items
          .map((item) => {
                'subtype': item.subtype,
                'weight_kg': item.weightKg,
                'quantity': item.quantity,
                'description': item.description,
                'notes': item.notes,
                'photos': item.photos,
                'is_quantity_only': item.isQuantityOnly,
                'is_no_site_weight': item.isNoSiteWeight,
              })
          .toList(),
      'saved_at': DateTime.now().toIso8601String(),
    };
  }

  static WasteCreateLoadDraftData? fromJsonString(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final items = <WasteItem>[];
      for (final entry in (data['items'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final photos = <String>[];
        for (final path in (entry['photos'] as List? ?? const [])) {
          if (path is String && path.isNotEmpty && File(path).existsSync()) {
            photos.add(path);
          }
        }
        items.add(WasteItem(
          loadId: 'temp',
          subtype: entry['subtype'] as String? ?? '',
          weightKg: (entry['weight_kg'] as num?)?.toDouble() ?? 0,
          quantity: entry['quantity'] as int?,
          description: entry['description'] as String?,
          notes: entry['notes'] as String?,
          photos: photos,
          isQuantityOnly: entry['is_quantity_only'] == true,
          isNoSiteWeight: entry['is_no_site_weight'] == true,
        ));
      }
      return WasteCreateLoadDraftData(
        createSubmitRef: data['create_submit_ref'] as String? ?? '',
        driverName: data['driver_name'] as String? ?? '',
        vehicleReg: data['vehicle_reg'] as String? ?? '',
        trailerReg: data['trailer_reg'] as String?,
        paperDocumentRef: data['paper_document_ref'] as String?,
        notes: data['notes'] as String?,
        contractorId: data['contractor_id'] as String?,
        selectedTypeIds: (data['selected_type_ids'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        timeIn: data['time_in'] as String?,
        timeOut: data['time_out'] as String?,
        items: items,
        selectedStockIds: (data['selected_stock_ids'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        selectedStockSnapshots: [
          for (final entry
              in (data['selected_stock_snapshots'] as List? ?? const []))
            if (entry is Map)
              Map<String, dynamic>.from(entry),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required String? clockNo,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey(clockNo), jsonEncode(payload));
  }

  static Future<WasteCreateLoadDraftData?> load(String? clockNo) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey(clockNo));
    if (raw == null || raw.isEmpty) return null;
    return fromJsonString(raw);
  }

  static Future<void> clear(String? clockNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey(clockNo));
  }
}

class WasteCreateLoadDraftData {
  final String createSubmitRef;
  final String driverName;
  final String vehicleReg;
  final String? trailerReg;
  final String? paperDocumentRef;
  final String? notes;
  final String? contractorId;
  final List<String> selectedTypeIds;
  final String? timeIn;
  final String? timeOut;
  final List<WasteItem> items;
  final List<String> selectedStockIds;
  final List<Map<String, dynamic>> selectedStockSnapshots;

  const WasteCreateLoadDraftData({
    required this.createSubmitRef,
    required this.driverName,
    required this.vehicleReg,
    this.trailerReg,
    this.paperDocumentRef,
    this.notes,
    this.contractorId,
    required this.selectedTypeIds,
    this.timeIn,
    this.timeOut,
    required this.items,
    required this.selectedStockIds,
    this.selectedStockSnapshots = const [],
  });
}