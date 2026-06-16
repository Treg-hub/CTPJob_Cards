import '../models/employee.dart';
import '../models/fleet_settings.dart';
import '../models/waste_settings.dart';

enum UserRole { technician, manager, admin, operator }

/// Infers a [UserRole] from an [Employee] based on `position` and `department`.
///
/// The `Employee` model has no explicit role field — role is derived from the
/// position string. Admin is *not* inferred here; it is granted at runtime via
/// the password gate in `SettingsScreen` and the `AdminScreen` does its own
/// authorisation. Treat the result as the user's day-to-day workflow role.
///
/// Returns [UserRole.operator] when [employee] is null or position doesn't
/// match any known technician/manager pattern (operators are the default).
UserRole roleFromEmployee(Employee? employee) {
  if (employee == null) return UserRole.operator;
  final pos = employee.position.toLowerCase();
  if (pos.contains('manager')) return UserRole.manager;
  // Broad substring match — covers "Mechanic", "Mechanical", "Diesel Mechanic",
  // "Electrical", "Electrician", "Auto Electrician", "Technician",
  // "Maintenance Technician". Manager is checked first so "Mechanical Manager"
  // still resolves to manager.
  if (pos.contains('mechanic') ||
      pos.contains('electric') ||
      pos.contains('technician') ||
      pos.contains('building maintenance') ||
      (employee.department == 'Pre Press' && pos.contains('specialist'))) {
    return UserRole.technician;
  }
  return UserRole.operator;
}

/// True when [employee]'s department implies factory-wide manager visibility
/// (e.g. workshop-wide rather than scoped to one production department).
bool isSuperManager(Employee? employee) {
  return (employee?.department.toLowerCase() ?? '') == 'general';
}

/// Copper inventory whitelist — used by HomeScreen to show the Copper tab.
const Set<String> _copperAuthorizedClockNos = {'22', '5421', '20'};

bool isCopperAuthorized(Employee? employee) {
  return _copperAuthorizedClockNos.contains(employee?.clockNo ?? '');
}

/// True when [employee] has the `isAdmin` flag set in their Firestore document.
bool isAdmin(Employee? employee) {
  return employee?.isAdmin ?? false;
}

// =============================================================================
// WASTE TRACK (WasteTrack) role helpers
// =============================================================================
// All roles are config-driven via WasteSettings (waste_settings/config).
//   - Admin:            reuses isAdmin() — Employee.isAdmin Firestore field
//   - Security Manager: clockNo in WasteSettings.managerClockNos
//   - Security Guard:   clockNo in WasteSettings.guardClockNos
// =============================================================================

/// Returns true if this user should have full WasteTrack Admin rights
/// (reuses the global isAdmin check).
bool isWasteAdmin(Employee? employee) {
  return isAdmin(employee);
}

/// Returns true if the employee's clock number is in the manager allow-list.
bool isSecurityManager(Employee? employee, WasteSettings? settings) {
  if (employee == null || settings == null) return false;
  return settings.managerClockNos.contains(employee.clockNo);
}

/// Returns true if the employee's clock number is in the guard allow-list.
bool isSecurityGuard(Employee? employee, WasteSettings? settings) {
  if (employee == null || settings == null) return false;
  return settings.guardClockNos.contains(employee.clockNo);
}

/// Convenience: any WasteTrack user (Admin, Security Manager, or Security Guard).
bool isWasteUser(Employee? employee, WasteSettings? settings) {
  return isWasteAdmin(employee) ||
      isSecurityManager(employee, settings) ||
      isSecurityGuard(employee, settings);
}

// =============================================================================
// FLEET MAINTENANCE role helpers
// =============================================================================
// Fleet roles are derived from Employee fields + FleetSettings config:
//   - Fleet Mechanic:     clockNo in fleet_settings.mechanicClockNos
//   - Fleet Reporter:     employee.department in fleet_settings.reporterDepartments
//   - Fleet Cost Manager: employee.clockNo in fleet_settings.costManagerClockNos
//   - Fleet Admin:        reuses isAdmin() — Employee.isAdmin Firestore field
// =============================================================================

bool _clockNoInAllowList(String? clockNo, List<String> allowList) {
  final normalized = FleetSettings.normalizeClockNo(clockNo);
  if (normalized.isEmpty) return false;
  return allowList.any(
    (allowed) => FleetSettings.normalizeClockNo(allowed) == normalized,
  );
}

/// True when the employee's clock number is in the mechanic allow-list.
bool isFleetMechanic(Employee? employee, FleetSettings? settings) {
  if (employee == null || settings == null) return false;
  return _clockNoInAllowList(employee.clockNo, settings.mechanicClockNos);
}

/// True when the employee's department is in the configurable reporter allow-list.
bool isFleetReporter(Employee? employee, FleetSettings? settings) {
  if (employee == null || settings == null) return false;
  return settings.reporterDepartments.contains(employee.department);
}

/// True when the employee's clock number is in the cost-manager allow-list.
bool isFleetCostManager(Employee? employee, FleetSettings? settings) {
  if (employee == null || settings == null) return false;
  return _clockNoInAllowList(employee.clockNo, settings.costManagerClockNos);
}

/// True when the employee has full fleet admin rights (reuses global isAdmin).
bool isFleetAdmin(Employee? employee) => isAdmin(employee);

/// Convenience: any Fleet user (shows Fleet tab when true).
bool isFleetUser(Employee? employee, FleetSettings? settings) {
  return isFleetMechanic(employee, settings) ||
      isFleetAdmin(employee) ||
      isFleetReporter(employee, settings) ||
      isFleetCostManager(employee, settings);
}

/// Any fleet role can report faults (reporters, mechanics, cost managers, admins).
bool canReportFleetIssue(Employee? employee, FleetSettings? settings) {
  if (settings == null || !settings.fleetEnabled) return false;
  return isFleetUser(employee, settings);
}

// =============================================================================
// BUILDING MAINTENANCE role helpers
// =============================================================================

/// True when the employee is a Building Maintenance worker.
/// Position must contain "building maintenance" (case-insensitive).
bool isBuildingMaintenance(Employee? employee) {
  if (employee == null) return false;
  return employee.position.toLowerCase().contains('building maintenance');
}

// =============================================================================
// PRE PRESS SPECIALIST role helpers
// =============================================================================

/// True when the employee is the Pre Press Specialist.
/// Double-gated on department + position to avoid false matches.
bool isPrepressSpecialist(Employee? employee) {
  if (employee == null) return false;
  return employee.department == 'Pre Press' &&
      employee.position.toLowerCase().contains('specialist');
}

// =============================================================================
// INK FACTORY role helpers
// =============================================================================
// Ink Factory (production stock-inventory module) is gated by DEPARTMENT
// membership — any position in "Ink Factory" is an operator. Admins also have
// access. Cost/value entry (purchase cost, revaluation), month-end adjustments
// and corrections are MANAGER-gated: position contains "manager" OR isAdmin.
// =============================================================================

const String inkDepartment = 'Ink Factory';

// =============================================================================
// LURGI role helpers
// =============================================================================
// Lurgi operates the ink and toloul meters daily (target 06:00). During the
// transition rollout, Ink Factory users also retain meter-entry access.
// =============================================================================

const String lurgiDepartment = 'Lurgi';

/// True when the employee is in the Lurgi department (plus admins).
bool isLurgiUser(Employee? employee) {
  if (employee == null) return false;
  return employee.department == lurgiDepartment || isAdmin(employee);
}

/// Can enter meter readings — Lurgi (primary duty) or Ink Factory (transition).
bool isInkMeterUser(Employee? employee) =>
    isLurgiUser(employee) || isInkUser(employee);

/// Any Ink Factory user (operators + managers), plus admins. Shows the Ink hub.
bool isInkUser(Employee? employee) {
  if (employee == null) return false;
  return employee.department == inkDepartment || isAdmin(employee);
}

/// Ink manager — may enter costs/revaluations, run month-end adjustments and
/// corrections. Admins always qualify.
bool isInkManager(Employee? employee) {
  if (employee == null) return false;
  if (isAdmin(employee)) return true;
  return isInkUser(employee) &&
      employee.position.toLowerCase().contains('manager');
}
