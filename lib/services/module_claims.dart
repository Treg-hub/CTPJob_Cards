/// Cached module participation flags from the ID token (Phase 2 prep).
///
/// Populated by [AuthClaimsService] after `setCustomClaims`. Old tokens / failed
/// refresh leave flags unset — [role.dart] then falls back to `*_settings` lists
/// so live behaviour is unchanged until claims are present.
class ModuleClaims {
  ModuleClaims._();
  static final ModuleClaims instance = ModuleClaims._();

  bool? isFleetMechanic;
  bool? isFleetReporter;
  bool? isFleetCostManager;
  bool? isSecurityManager;
  bool? isSecurityStaff;
  bool? isWasteStaff;
  bool? isInkStaff;

  bool get hasAny =>
      isFleetMechanic != null ||
      isFleetReporter != null ||
      isFleetCostManager != null ||
      isSecurityManager != null ||
      isSecurityStaff != null ||
      isWasteStaff != null ||
      isInkStaff != null;

  void clear() {
    isFleetMechanic = null;
    isFleetReporter = null;
    isFleetCostManager = null;
    isSecurityManager = null;
    isSecurityStaff = null;
    isWasteStaff = null;
    isInkStaff = null;
  }

  void applyFromTokenClaims(Map<String, dynamic> claims) {
    bool? asBool(dynamic v) => v is bool ? v : null;
    isFleetMechanic = asBool(claims['isFleetMechanic']);
    isFleetReporter = asBool(claims['isFleetReporter']);
    isFleetCostManager = asBool(claims['isFleetCostManager']);
    isSecurityManager = asBool(claims['isSecurityManager']);
    isSecurityStaff = asBool(claims['isSecurityStaff']);
    isWasteStaff = asBool(claims['isWasteStaff']);
    isInkStaff = asBool(claims['isInkStaff']);
  }
}
