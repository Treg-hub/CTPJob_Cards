import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Local draft for an in-progress [WasteBeginCollectionScreen] session.
abstract final class WasteBeginCollectionDraft {
  static String prefsKey(String loadId, String? clockNo) =>
      'wasteBeginCollectionDraft_${loadId}_${clockNo ?? 'unknown'}';

  static Map<String, dynamic> toJson({
    required String collectionSubmitRef,
    required String driverName,
    required String vehicleReg,
    String? trailerReg,
    required String paperDocumentRef,
    required String timeIn,
    String? timeOut,
    required List<Map<String, dynamic>> items,
    required List<String> loadPhotoPaths,
    String? signatureLocalPath,
    bool adminOverrideActive = false,
  }) {
    return {
      'collection_submit_ref': collectionSubmitRef,
      'driver_name': driverName,
      'vehicle_reg': vehicleReg,
      'trailer_reg': trailerReg,
      'paper_document_ref': paperDocumentRef,
      'time_in': timeIn,
      'time_out': timeOut,
      'admin_override_active': adminOverrideActive,
      'load_photo_paths': loadPhotoPaths,
      if (signatureLocalPath != null && signatureLocalPath.isNotEmpty)
        'signature_local_path': signatureLocalPath,
      'items': items,
      'saved_at': DateTime.now().toIso8601String(),
    };
  }

  static WasteBeginCollectionDraftData? fromJsonString(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final loadPhotos = <String>[];
      for (final path in (data['load_photo_paths'] as List? ?? const [])) {
        if (path is String && path.isNotEmpty && File(path).existsSync()) {
          loadPhotos.add(path);
        }
      }
      final items = <Map<String, dynamic>>[];
      for (final entry in (data['items'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final photos = <String>[];
        for (final path in (entry['photo_paths'] as List? ?? const [])) {
          if (path is String && path.isNotEmpty && File(path).existsSync()) {
            photos.add(path);
          }
        }
        items.add({
          'subtype': entry['subtype'],
          'weight_kg': entry['weight_kg'],
          'quantity': entry['quantity'],
          'notes': entry['notes'],
          'photo_paths': photos,
          'stock_id': entry['stock_id'],
          'linked_ibc_numbers': entry['linked_ibc_numbers'],
          'is_quantity_only': entry['is_quantity_only'] == true,
          'is_no_site_weight': entry['is_no_site_weight'] == true,
        });
      }
      String? signaturePath;
      final rawSig = data['signature_local_path'] as String?;
      if (rawSig != null && rawSig.isNotEmpty && File(rawSig).existsSync()) {
        signaturePath = rawSig;
      }
      return WasteBeginCollectionDraftData(
        collectionSubmitRef: data['collection_submit_ref'] as String? ?? '',
        driverName: data['driver_name'] as String? ?? '',
        vehicleReg: data['vehicle_reg'] as String? ?? '',
        trailerReg: data['trailer_reg'] as String?,
        paperDocumentRef: data['paper_document_ref'] as String? ?? '',
        timeIn: data['time_in'] as String? ?? '',
        timeOut: data['time_out'] as String?,
        adminOverrideActive: data['admin_override_active'] == true,
        loadPhotoPaths: loadPhotos,
        signatureLocalPath: signaturePath,
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required String loadId,
    required String? clockNo,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey(loadId, clockNo), jsonEncode(payload));
  }

  static Future<WasteBeginCollectionDraftData?> load(
    String loadId,
    String? clockNo,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey(loadId, clockNo));
    if (raw == null || raw.isEmpty) return null;
    return fromJsonString(raw);
  }

  static Future<void> clear(String loadId, String? clockNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey(loadId, clockNo));
  }
}

class WasteBeginCollectionDraftData {
  final String collectionSubmitRef;
  final String driverName;
  final String vehicleReg;
  final String? trailerReg;
  final String paperDocumentRef;
  final String timeIn;
  final String? timeOut;
  final bool adminOverrideActive;
  final List<String> loadPhotoPaths;
  final String? signatureLocalPath;
  final List<Map<String, dynamic>> items;

  const WasteBeginCollectionDraftData({
    required this.collectionSubmitRef,
    required this.driverName,
    required this.vehicleReg,
    this.trailerReg,
    required this.paperDocumentRef,
    required this.timeIn,
    this.timeOut,
    required this.adminOverrideActive,
    required this.loadPhotoPaths,
    this.signatureLocalPath,
    required this.items,
  });
}