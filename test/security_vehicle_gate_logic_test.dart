import 'package:ctp_job_cards/models/parsed_document.dart';
import 'package:ctp_job_cards/models/security_scan_result.dart';
import 'package:ctp_job_cards/services/security_document_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecurityScanResult', () {
    test('success carries document', () {
      final doc = SecurityDocumentParser.manualLicenseDisc(vehicleReg: 'BX33HKZN');
      final result = SecurityScanResult.success(doc);
      expect(result.hasDocument, isTrue);
      expect(result.skipped, isFalse);
      expect(result.cantScan, isFalse);
      expect(result.document?.vehicleReg, 'BX33HKZN');
    });

    test('skipped and cantScan have no document', () {
      expect(SecurityScanResult.skippedScan().hasDocument, isFalse);
      expect(SecurityScanResult.cantScanDisc().cantScan, isTrue);
    });
  });

  group('manual license disc', () {
    test('normalizes reg for gate header display', () {
      final doc = SecurityDocumentParser.manualLicenseDisc(
        vehicleReg: 'bx33hkzn',
        vehicleMake: 'HYUNDAI',
      );
      expect(doc.documentType, SecurityDocumentType.licenseDisc);
      expect(doc.vehicleReg, isNotNull);
    });
  });
}