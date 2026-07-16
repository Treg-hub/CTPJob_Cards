/// Cached custom-claim flags from the ID token.
///
/// Populated by [AuthClaimsService] after `setCustomClaims`. Old tokens / failed
/// refresh leave flags unset — [role.dart] then falls back to `*_settings` lists
/// / employee fields so live behaviour is unchanged until claims are present.
///
/// Admin UI persona testing must not use these flags: they always describe the
/// **real** Firebase session. See [suppressTokenClaimsForUi].
///
/// **Phase 9 dual isAdmin:** [isAdmin] is the token claim (from locked
/// `admins/{uid}` via setCustomClaims). [role.dart] `isAdmin(employee)` prefers
/// this when non-null, else falls back to `Employee.isAdmin`.
class ModuleClaims {
  ModuleClaims._();
  static final ModuleClaims instance = ModuleClaims._();

  /// Token `isAdmin` claim — null until claims applied / when key absent.
  bool? isAdmin;

  bool? isFleetMechanic;
  bool? isFleetReporter;
  bool? isFleetCostManager;
  bool? isSecurityManager;
  bool? isSecurityStaff;
  bool? isWasteStaff;
  bool? isInkStaff;

  /// When true, [role.dart] ignores token module flags and derives access only
  /// from the effective (persona) employee + `*_settings` lists. Set by
  /// [PersonaNotifier] for the duration of admin role testing.
  bool suppressTokenClaimsForUi = false;

  /// Token flags for UI gating — null while persona testing so helpers fall
  /// through to department / clock-list checks on the persona employee.
  bool? get uiIsAdmin => suppressTokenClaimsForUi ? null : isAdmin;
  bool? get uiIsFleetMechanic =>
      suppressTokenClaimsForUi ? null : isFleetMechanic;
  bool? get uiIsFleetReporter =>
      suppressTokenClaimsForUi ? null : isFleetReporter;
  bool? get uiIsFleetCostManager =>
      suppressTokenClaimsForUi ? null : isFleetCostManager;
  bool? get uiIsSecurityManager =>
      suppressTokenClaimsForUi ? null : isSecurityManager;
  bool? get uiIsSecurityStaff =>
      suppressTokenClaimsForUi ? null : isSecurityStaff;
  bool? get uiIsWasteStaff =>
      suppressTokenClaimsForUi ? null : isWasteStaff;
  bool? get uiIsInkStaff => suppressTokenClaimsForUi ? null : isInkStaff;

  bool get hasAny =>
      isAdmin != null ||
      isFleetMechanic != null ||
      isFleetReporter != null ||
      isFleetCostManager != null ||
      isSecurityManager != null ||
      isSecurityStaff != null ||
      isWasteStaff != null ||
      isInkStaff != null;

  void clear() {
    isAdmin = null;
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
    // isAdmin is always a bool when set by setCustomClaims; treat missing as null
    // so dual-admin can fall back to Employee.isAdmin before first refresh.
    isAdmin = claims.containsKey('isAdmin')
        ? claims['isAdmin'] == true
        : null;
    isFleetMechanic = asBool(claims['isFleetMechanic']);
    isFleetReporter = asBool(claims['isFleetReporter']);
    isFleetCostManager = asBool(claims['isFleetCostManager']);
    isSecurityManager = asBool(claims['isSecurityManager']);
    isSecurityStaff = asBool(claims['isSecurityStaff']);
    isWasteStaff = asBool(claims['isWasteStaff']);
    isInkStaff = asBool(claims['isInkStaff']);
  }
}
