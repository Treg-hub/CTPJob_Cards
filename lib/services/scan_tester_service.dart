import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/collections.dart';
import '../models/parsed_document.dart' show ParsedDocument, SecurityDocumentType;
import 'security_document_parser.dart';

/// Cross-module catalogue — mirrors web/ctp-pulse/src/lib/scanTester.ts.
class ScanTesterCatalog {
  ScanTesterCatalog._();

  static const modules = [
    'security',
    'ink',
    'waste',
    'fleet',
    'stock',
    'other',
  ];

  static const useCases = <String, List<String>>{
    'security': ['licence_disc', 'national_id', 'driver_licence', 'unknown'],
    'ink': ['ibc_receive', 'shipment_label', 'unknown'],
    'waste': ['unknown'],
    'fleet': ['unknown'],
    'stock': ['raw_material', 'finished_goods', 'unknown'],
    'other': ['unknown'],
  };
}

class ScanBarcodeEntry {
  const ScanBarcodeEntry({required this.format, required this.payload});

  final String format;
  final String payload;

  Map<String, dynamic> toFirestore() => {
        'format': format,
        'payload': payload,
      };
}

/// Saves admin scan-tester samples to Firestore. Does not touch production
/// security gate or ink IBC receive flows.
class ScanTesterService {
  ScanTesterService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String normalizeBarcodeFormat(BarcodeFormat? format) {
    final name = (format?.name ?? '').toLowerCase();
    if (name.contains('pdf')) return 'pdf417';
    if (name.contains('code128') || name.contains('code_128')) return 'code128';
    if (name.contains('data_matrix') || name.contains('datamatrix')) {
      return 'datamatrix';
    }
    if (name.contains('qr')) return 'qr';
    if (name.contains('code39') || name.contains('code_39')) return 'code39';
    return 'unknown';
  }

  static Map<String, dynamic> buildParserPreview({
    required String module,
    required String useCase,
    required String rawPayload,
    List<ScanBarcodeEntry>? allBarcodes,
  }) {
    if (module == 'security') {
      return {'security': _previewSecurityParse(useCase, rawPayload)};
    }
    if (module == 'ink' && useCase == 'ibc_receive') {
      final payloads = allBarcodes != null && allBarcodes.isNotEmpty
          ? allBarcodes.map((b) => b.payload).toList()
          : [rawPayload];
      return {
        'ink': {
          'status': 'provision_only',
          'message':
              'Ink IBC parser preview is not wired in Scan Tester yet. '
              'Production receive flow is unchanged. Save raw barcode(s) here to onboard later.',
          'barcodeCount': payloads.length,
          'payloads': payloads,
        },
      };
    }
    return {'note': 'No parser preview for this module/use_case yet.'};
  }

  static Map<String, dynamic> _previewSecurityParse(
    String useCase,
    String raw,
  ) {
    final ParsedDocument doc;
    switch (useCase) {
      case 'licence_disc':
        doc = SecurityDocumentParser.parseLicenseDisc(raw);
        break;
      case 'national_id':
        doc = SecurityDocumentParser.parseIdDocument(raw);
        break;
      case 'driver_licence':
        doc = SecurityDocumentParser.parseDriverLicence(raw);
        break;
      default:
        doc = SecurityDocumentParser.parseBarcode(raw);
    }
    return _parsedDocumentToPreview(doc);
  }

  static Map<String, dynamic> _parsedDocumentToPreview(ParsedDocument doc) {
    String? expiryWarning;
    if (doc.expiryDate != null) {
      final today = DateTime.now();
      final d = DateTime(doc.expiryDate!.year, doc.expiryDate!.month, doc.expiryDate!.day);
      final t = DateTime(today.year, today.month, today.day);
      if (d.isBefore(t)) {
        expiryWarning = 'Expired (${d.toIso8601String().split('T').first})';
      } else {
        final days = d.difference(t).inDays;
        if (days <= 7) expiryWarning = 'Expires in $days day(s)';
      }
    }

    final type = switch (doc.documentType) {
      SecurityDocumentType.licenseDisc => 'license_disc',
      SecurityDocumentType.idDocument => 'id_document',
      SecurityDocumentType.driverLicence => 'driver_licence',
      SecurityDocumentType.unknown => 'unknown',
    };

    return {
      'documentType': type,
      if (doc.vehicleReg != null) 'vehicleReg': doc.vehicleReg,
      if (doc.expiryDate != null)
        'expiryDate': doc.expiryDate!.toIso8601String().split('T').first,
      if (doc.vehicleMake != null) 'vehicleMake': doc.vehicleMake,
      if (doc.vehicleModel != null) 'vehicleModel': doc.vehicleModel,
      if (doc.vehicleColour != null) 'vehicleColour': doc.vehicleColour,
      if (doc.firstName != null) 'firstName': doc.firstName,
      if (doc.lastName != null) 'lastName': doc.lastName,
      if (doc.idNumber != null) 'idNumber': doc.idNumber,
      if (expiryWarning != null) 'expiryWarning': expiryWarning,
      'rawPayload': doc.rawPayload ?? '',
    };
  }

  Future<String> saveSample({
    required String module,
    required String useCase,
    required String barcodeFormat,
    required String rawPayload,
    List<ScanBarcodeEntry>? allBarcodes,
    String? notes,
    required String capturedByUid,
    required String capturedByClockNo,
    String? capturedByName,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    final parserPreview = buildParserPreview(
      module: module,
      useCase: useCase,
      rawPayload: rawPayload,
      allBarcodes: allBarcodes,
    );

    final ref = await _db.collection(Collections.pulseScanSamples).add({
      'module': module,
      'use_case': useCase,
      'barcode_format': barcodeFormat,
      'raw_payload': rawPayload,
      if (allBarcodes != null && allBarcodes.length > 1)
        'all_barcodes': allBarcodes.map((b) => b.toFirestore()).toList(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'parser_preview': parserPreview,
      'golden_fixture': false,
      'captured_at': FieldValue.serverTimestamp(),
      'captured_by_uid': capturedByUid,
      'captured_by_clock_no': capturedByClockNo,
      if (capturedByName != null && capturedByName.trim().isNotEmpty)
        'captured_by_name': capturedByName.trim(),
      'app_version': 'ctp-job-cards-$appVersion',
    });
    return ref.id;
  }
}