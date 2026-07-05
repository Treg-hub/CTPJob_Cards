import '../models/security_entry.dart';

/// Pure gate-flow helpers — keep scan-chain and form-visibility rules testable.
class SecurityVehicleGateLogic {
  SecurityVehicleGateLogic._();

  /// Resolved flow after disc/vehicle context is applied.
  static GateFlowKind resolveFlowKind({
    required bool isCompanyCarMode,
    required SecurityDirection direction,
    required bool companyVehicleResolved,
  }) {
    if (companyVehicleResolved && isCompanyCarMode) {
      return direction == SecurityDirection.out
          ? GateFlowKind.companyCarExit
          : GateFlowKind.companyCarReturn;
    }
    return direction == SecurityDirection.out
        ? GateFlowKind.visitorExit
        : GateFlowKind.visitorEntry;
  }

  /// Auto-open the driver's licence scanner after the disc (or company-car pick).
  static bool shouldChainDriverLicenceScan({
    required bool isCompanyCarMode,
    required SecurityDirection direction,
    required bool companyVehicleResolved,
    required bool licenceUnavailable,
    required bool hasDriverLicence,
  }) {
    if (hasDriverLicence || licenceUnavailable) return false;

    final flow = resolveFlowKind(
      isCompanyCarMode: isCompanyCarMode,
      direction: direction,
      companyVehicleResolved: companyVehicleResolved,
    );

    return switch (flow) {
      GateFlowKind.visitorEntry => true,
      GateFlowKind.companyCarExit => true,
      _ => false,
    };
  }

  /// Header link "Not a registered company car" — **company-car screen only**
  /// when a disc was scanned but did not match the registry.
  static bool shouldShowCompanyRegistryHint({
    required bool isCompanyCarMode,
    required bool hasDiscScan,
    required bool companyVehicleResolved,
  }) {
    return isCompanyCarMode && hasDiscScan && !companyVehicleResolved;
  }

  /// Visitor entry opt-out when the driver could not / did not scan a licence.
  static bool shouldShowLicenceNotScannedOptOut({
    required GateFlowKind flow,
    required bool hasDriverLicence,
  }) {
    return flow == GateFlowKind.visitorEntry && !hasDriverLicence;
  }

  /// Reason / override chips — only when audit documentation is actually needed.
  static bool shouldShowOverrideSection({
    required GateFlowKind flow,
    required bool licenceUnavailable,
    required bool complianceWarn,
    required bool hasValidDriverLicence,
  }) {
    return switch (flow) {
      // After a valid licence scan, only expiry compliance needs override chips —
      // not the "no licence" opt-out path (avoids stale checkbox/skip state).
      GateFlowKind.visitorEntry => hasValidDriverLicence
          ? complianceWarn
          : (licenceUnavailable || complianceWarn),
      GateFlowKind.companyCarExit => complianceWarn,
      _ => false,
    };
  }

  /// Whether the "No licence" chip belongs on the override row for this state.
  static bool shouldIncludeNoLicenceOverrideReason({
    required GateFlowKind flow,
    required bool licenceUnavailable,
  }) {
    return flow == GateFlowKind.visitorEntry && licenceUnavailable;
  }
}

/// Mirrors the private flow enum on [SecurityVehicleGateScreen] for tests + logic.
enum GateFlowKind {
  visitorEntry,
  visitorExit,
  companyCarExit,
  companyCarReturn,
}