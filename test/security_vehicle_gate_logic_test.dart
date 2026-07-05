import 'package:ctp_job_cards/models/parsed_document.dart';
import 'package:ctp_job_cards/models/security_entry.dart';
import 'package:ctp_job_cards/models/security_scan_result.dart';
import 'package:ctp_job_cards/services/security_document_parser.dart';
import 'package:ctp_job_cards/utils/security_vehicle_gate_logic.dart';
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

  group('SecurityVehicleGateLogic.resolveFlowKind', () {
    test('visitor entry when vehicle not on site', () {
      expect(
        SecurityVehicleGateLogic.resolveFlowKind(
          isCompanyCarMode: false,
          direction: SecurityDirection.in_,
          companyVehicleResolved: false,
        ),
        GateFlowKind.visitorEntry,
      );
    });

    test('visitor exit when vehicle already on site', () {
      expect(
        SecurityVehicleGateLogic.resolveFlowKind(
          isCompanyCarMode: false,
          direction: SecurityDirection.out,
          companyVehicleResolved: false,
        ),
        GateFlowKind.visitorExit,
      );
    });

    test('company car exit when registered car is on site', () {
      expect(
        SecurityVehicleGateLogic.resolveFlowKind(
          isCompanyCarMode: true,
          direction: SecurityDirection.out,
          companyVehicleResolved: true,
        ),
        GateFlowKind.companyCarExit,
      );
    });

    test('company car return when registered car is out on trip', () {
      expect(
        SecurityVehicleGateLogic.resolveFlowKind(
          isCompanyCarMode: true,
          direction: SecurityDirection.in_,
          companyVehicleResolved: true,
        ),
        GateFlowKind.companyCarReturn,
      );
    });

    test('unresolved company car falls back to visitor flow', () {
      expect(
        SecurityVehicleGateLogic.resolveFlowKind(
          isCompanyCarMode: true,
          direction: SecurityDirection.in_,
          companyVehicleResolved: false,
        ),
        GateFlowKind.visitorEntry,
      );
    });
  });

  group('SecurityVehicleGateLogic.shouldChainDriverLicenceScan', () {
    test('chains after visitor disc scan on entry (not on site)', () {
      expect(
        SecurityVehicleGateLogic.shouldChainDriverLicenceScan(
          isCompanyCarMode: false,
          direction: SecurityDirection.in_,
          companyVehicleResolved: false,
          licenceUnavailable: false,
          hasDriverLicence: false,
        ),
        isTrue,
      );
    });

    test('does not chain on visitor exit (vehicle already on site)', () {
      expect(
        SecurityVehicleGateLogic.shouldChainDriverLicenceScan(
          isCompanyCarMode: false,
          direction: SecurityDirection.out,
          companyVehicleResolved: false,
          licenceUnavailable: false,
          hasDriverLicence: false,
        ),
        isFalse,
      );
    });

    test('chains on company car exit after disc or dropdown pick', () {
      expect(
        SecurityVehicleGateLogic.shouldChainDriverLicenceScan(
          isCompanyCarMode: true,
          direction: SecurityDirection.out,
          companyVehicleResolved: true,
          licenceUnavailable: false,
          hasDriverLicence: false,
        ),
        isTrue,
      );
    });

    test('does not chain on company car return', () {
      expect(
        SecurityVehicleGateLogic.shouldChainDriverLicenceScan(
          isCompanyCarMode: true,
          direction: SecurityDirection.in_,
          companyVehicleResolved: true,
          licenceUnavailable: false,
          hasDriverLicence: false,
        ),
        isFalse,
      );
    });

    test('does not chain when licence already captured', () {
      expect(
        SecurityVehicleGateLogic.shouldChainDriverLicenceScan(
          isCompanyCarMode: false,
          direction: SecurityDirection.in_,
          companyVehicleResolved: false,
          licenceUnavailable: false,
          hasDriverLicence: true,
        ),
        isFalse,
      );
    });

    test('does not chain when visitor marked licence unavailable', () {
      expect(
        SecurityVehicleGateLogic.shouldChainDriverLicenceScan(
          isCompanyCarMode: false,
          direction: SecurityDirection.in_,
          companyVehicleResolved: false,
          licenceUnavailable: true,
          hasDriverLicence: false,
        ),
        isFalse,
      );
    });
  });

  group('SecurityVehicleGateLogic.shouldShowCompanyRegistryHint', () {
    test('hidden on visitor screen even when disc scanned', () {
      expect(
        SecurityVehicleGateLogic.shouldShowCompanyRegistryHint(
          isCompanyCarMode: false,
          hasDiscScan: true,
          companyVehicleResolved: false,
        ),
        isFalse,
      );
    });

    test('shown on company car screen when disc does not match registry', () {
      expect(
        SecurityVehicleGateLogic.shouldShowCompanyRegistryHint(
          isCompanyCarMode: true,
          hasDiscScan: true,
          companyVehicleResolved: false,
        ),
        isTrue,
      );
    });

    test('hidden when company car matched', () {
      expect(
        SecurityVehicleGateLogic.shouldShowCompanyRegistryHint(
          isCompanyCarMode: true,
          hasDiscScan: true,
          companyVehicleResolved: true,
        ),
        isFalse,
      );
    });
  });

  group('SecurityVehicleGateLogic.shouldShowLicenceNotScannedOptOut', () {
    test('shown on visitor entry without licence', () {
      expect(
        SecurityVehicleGateLogic.shouldShowLicenceNotScannedOptOut(
          flow: GateFlowKind.visitorEntry,
          hasDriverLicence: false,
        ),
        isTrue,
      );
    });

    test('hidden after licence scanned', () {
      expect(
        SecurityVehicleGateLogic.shouldShowLicenceNotScannedOptOut(
          flow: GateFlowKind.visitorEntry,
          hasDriverLicence: true,
        ),
        isFalse,
      );
    });

    test('hidden on company car exit', () {
      expect(
        SecurityVehicleGateLogic.shouldShowLicenceNotScannedOptOut(
          flow: GateFlowKind.companyCarExit,
          hasDriverLicence: false,
        ),
        isFalse,
      );
    });
  });

  group('SecurityVehicleGateLogic.shouldShowOverrideSection', () {
    test('hidden on visitor entry when licence scanned and compliant', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.visitorEntry,
          licenceUnavailable: false,
          complianceWarn: false,
          hasValidDriverLicence: true,
        ),
        isFalse,
      );
    });

    test('hidden when valid licence scanned despite stale licenceUnavailable', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.visitorEntry,
          licenceUnavailable: true,
          complianceWarn: false,
          hasValidDriverLicence: true,
        ),
        isFalse,
      );
    });

    test('shown when visitor opted out of licence scan', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.visitorEntry,
          licenceUnavailable: true,
          complianceWarn: false,
          hasValidDriverLicence: false,
        ),
        isTrue,
      );
    });

    test('shown when disc or licence expired', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.visitorEntry,
          licenceUnavailable: false,
          complianceWarn: true,
          hasValidDriverLicence: true,
        ),
        isTrue,
      );
    });

    test('shown when disc expired before licence scanned', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.visitorEntry,
          licenceUnavailable: false,
          complianceWarn: true,
          hasValidDriverLicence: false,
        ),
        isTrue,
      );
    });

    test('hidden on company car exit when compliant', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.companyCarExit,
          licenceUnavailable: false,
          complianceWarn: false,
          hasValidDriverLicence: true,
        ),
        isFalse,
      );
    });

    test('shown on company car exit when disc or licence expired', () {
      expect(
        SecurityVehicleGateLogic.shouldShowOverrideSection(
          flow: GateFlowKind.companyCarExit,
          licenceUnavailable: false,
          complianceWarn: true,
          hasValidDriverLicence: true,
        ),
        isTrue,
      );
    });
  });
}