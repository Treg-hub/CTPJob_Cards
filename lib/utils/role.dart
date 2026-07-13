import '../models/employee.dart';
import '../models/fleet_settings.dart';
import '../models/job_card.dart';
import '../models/security_settings.dart';
import '../models/waste_settings.dart';
import '../models/work_report_settings.dart';
import '../services/module_claims.dart';

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
      pos.contains('pre press specialist') ||
      (employee.department == 'Pre Press' && pos.contains('specialist'))) {
    return UserRole.technician;
  }
  return UserRole.operator;
}

/// Operators may only Start/Complete/Monitor non-Maintenance jobs when they
/// raised the fault themselves. Anyone explicitly assigned to a job card
/// (manager assign, auto-assign, or self-assign) may work it like a technician.
bool isOperatorRestrictedForJob(Employee? employee, JobCard job) {
  if (employee == null) return true;
  if (job.assignedClockNos?.contains(employee.clockNo) ?? false) return false;
  return roleFromEmployee(employee) == UserRole.operator &&
      job.type != JobType.maintenance;
}

/// True when [employee]'s department implies factory-wide manager visibility
/// (e.g. workshop-wide rather than scoped to one production department).
bool isSuperManager(Employee? employee) {
  return (employee?.department.toLowerCase() ?? '') == 'general';
}

/// Copper inventory access — used by HomeScreen to show the Copper tab.
/// Matches Firestore `canAccessCopper`: admin **or** Pre Press manager
/// (department Pre Press + position contains "manager"). No hard-coded clocks.
bool isCopperAuthorized(Employee? employee) {
  if (employee == null) return false;
  if (isAdmin(employee)) return true;
  final dept = employee.department.trim().toLowerCase();
  final pos = employee.position.trim().toLowerCase();
  return dept == 'pre press' && pos.contains('manager');
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

bool _clockNoInSecurityAllowList(String? clockNo, List<String> allowList) {
  final normalized = SecuritySettings.normalizeClockNo(clockNo);
  if (normalized.isEmpty) return false;
  return allowList.any(
    (allowed) => SecuritySettings.normalizeClockNo(allowed) == normalized,
  );
}

/// Security department + position Guard (WasteTrack / Site Security dept check).
bool isSecurityDeptGuard(Employee? employee) {
  if (employee == null) return false;
  return employee.department.trim() == 'Security' &&
      employee.position.toLowerCase().contains('guard');
}

/// Security department + position contains manager.
bool isSecurityDeptManager(Employee? employee) {
  if (employee == null) return false;
  return employee.department.trim() == 'Security' &&
      employee.position.toLowerCase().contains('manager');
}

/// WasteTrack Security Manager — claims flag OR dept/position OR waste_settings.
bool isSecurityManager(Employee? employee, WasteSettings? settings) {
  if (employee == null) return false;
  if (isWasteAdmin(employee)) return true;
  if (ModuleClaims.instance.uiIsSecurityManager == true) return true;
  if (isSecurityDeptManager(employee)) return true;
  if (settings == null) return false;
  return _clockNoInSecurityAllowList(
    employee.clockNo,
    settings.managerClockNos,
  );
}

/// WasteTrack Security Guard — claims / manager / dept / waste_settings list.
bool isSecurityGuard(Employee? employee, WasteSettings? settings) {
  if (employee == null) return false;
  if (isSecurityManager(employee, settings)) return true;
  if (ModuleClaims.instance.uiIsSecurityStaff == true ||
      ModuleClaims.instance.uiIsWasteStaff == true) {
    return true;
  }
  if (isSecurityDeptGuard(employee)) return true;
  if (settings == null) return false;
  return _clockNoInSecurityAllowList(
    employee.clockNo,
    settings.guardClockNos,
  );
}

/// Convenience: any WasteTrack user (Admin, Security Manager, or Security Guard).
bool isWasteUser(Employee? employee, WasteSettings? settings) {
  return isWasteAdmin(employee) ||
      isSecurityManager(employee, settings) ||
      isSecurityGuard(employee, settings);
}

/// Browse on-site stock inventory (list screen, banner). Guards link at collection only.
bool canViewWasteStockInventory(Employee? employee, WasteSettings? settings) {
  return isWasteAdmin(employee) || isSecurityManager(employee, settings);
}

/// Manager-only copper ready-to-sell panel on the Waste tab.
bool canViewCopperReadyPanel(Employee? employee, WasteSettings? settings) {
  return canViewWasteStockInventory(employee, settings);
}

// =============================================================================
// SITE SECURITY module role helpers (security_settings/config)
// =============================================================================

bool _isSiteSecurityManager(Employee? employee, SecuritySettings? settings) {
  if (employee == null) return false;
  if (isAdmin(employee)) return true;
  if (ModuleClaims.instance.uiIsSecurityManager == true) return true;
  if (settings == null) return false;
  if (isSecurityDeptManager(employee)) return true;
  return _clockNoInSecurityAllowList(
    employee.clockNo,
    settings.managerClockNos,
  );
}

bool _isSiteSecurityGuard(Employee? employee, SecuritySettings? settings) {
  if (employee == null) return false;
  if (_isSiteSecurityManager(employee, settings)) return true;
  if (ModuleClaims.instance.uiIsSecurityStaff == true) return true;
  if (settings == null) return false;
  if (isSecurityDeptGuard(employee)) return true;
  return _clockNoInSecurityAllowList(
    employee.clockNo,
    settings.guardClockNos,
  );
}

/// Any Site Security user (admin, manager, or guard).
bool isSecurityUser(Employee? employee, SecuritySettings? settings) {
  return isAdmin(employee) ||
      _isSiteSecurityManager(employee, settings) ||
      _isSiteSecurityGuard(employee, settings);
}

/// Manager or admin — vehicle cost entry, etc.
bool isSecurityCostManager(Employee? employee, SecuritySettings? settings) {
  return isAdmin(employee) || _isSiteSecurityManager(employee, settings);
}

/// Gate for showing the Security tab and quick actions.
bool canUseSecurityModule(Employee? employee, SecuritySettings? settings) {
  if (settings == null || !settings.securityEnabled) return false;
  return isSecurityUser(employee, settings);
}

/// Site security guard floor role — waste + gate capture; not manager desk or costing.
bool isSiteSecurityGuardOnly(Employee? employee, SecuritySettings? settings) {
  if (!canUseSecurityModule(employee, settings)) return false;
  return !isSecurityCostManager(employee, settings);
}

/// Filter stock rows in inventory views. Collection-day link sheets may show more.
bool canViewWasteStockInInventory({
  required Employee? employee,
  required WasteSettings? settings,
  required String visibility,
}) {
  if (visibility != 'manager_only') return isWasteUser(employee, settings);
  return canViewWasteStockInventory(employee, settings);
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
  if (employee == null) return false;
  if (ModuleClaims.instance.uiIsFleetMechanic == true) return true;
  if (settings == null) return false;
  return _clockNoInAllowList(employee.clockNo, settings.mechanicClockNos);
}

/// True when the employee's department is in the configurable reporter allow-list.
bool isFleetReporter(Employee? employee, FleetSettings? settings) {
  if (employee == null) return false;
  if (ModuleClaims.instance.uiIsFleetReporter == true) return true;
  if (settings == null) return false;
  return settings.reporterDepartments.contains(employee.department);
}

/// True when the employee's clock number is in the cost-manager allow-list.
bool isFleetCostManager(Employee? employee, FleetSettings? settings) {
  if (employee == null) return false;
  if (ModuleClaims.instance.uiIsFleetCostManager == true) return true;
  if (settings == null) return false;
  return _clockNoInAllowList(employee.clockNo, settings.costManagerClockNos);
}

/// True when the employee has full fleet admin rights (reuses global isAdmin).
bool isFleetAdmin(Employee? employee) => isAdmin(employee);

/// Floor fleet roles — reporters and mechanics (mobile Fleet tab).
bool isFleetMobileUser(Employee? employee, FleetSettings? settings) {
  if (settings == null || !settings.fleetEnabled) return false;
  return isFleetReporter(employee, settings) ||
      isFleetMechanic(employee, settings);
}

/// Convenience: shows Fleet tab on mobile when true.
bool isFleetUser(Employee? employee, FleetSettings? settings) {
  return isFleetMobileUser(employee, settings);
}

/// Report faults from the home quick action (reporters only).
bool canReportFleetIssue(Employee? employee, FleetSettings? settings) {
  if (settings == null || !settings.fleetEnabled) return false;
  return isFleetReporter(employee, settings);
}

/// Daily pre-use safety check from the home quick action (reporters only).
bool canDoFleetDailyCheck(Employee? employee, FleetSettings? settings) {
  if (settings == null || !settings.fleetEnabled) return false;
  return isFleetReporter(employee, settings);
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
  final pos = employee.position.toLowerCase();
  // Live roster: one specialist is Workshop | Pre Press Specialist (dept mismatch).
  return pos.contains('pre press specialist') ||
      (employee.department == 'Pre Press' && pos.contains('specialist'));
}

// =============================================================================
// MY TIMESHEET (work_report) role helpers
// =============================================================================

bool _workReportClockInList(String? clockNo, List<String> allowList) {
  final normalized = WorkReportSettings.normalizeClockNo(clockNo);
  if (normalized.isEmpty) return false;
  return allowList.any(
    (allowed) => WorkReportSettings.normalizeClockNo(allowed) == normalized,
  );
}

/// Worker tile + screens, or admin viewer/editor.
bool canUseWorkReportModule(Employee? employee, WorkReportSettings? settings) {
  if (settings == null || !settings.enabled) return false;
  if (isAdmin(employee)) return true;
  return _workReportClockInList(employee?.clockNo, settings.enabledClockNos);
}

/// Non-admin enrolled worker (Home tile).
bool isWorkReportWorker(Employee? employee, WorkReportSettings? settings) {
  if (settings == null || !settings.enabled) return false;
  return _workReportClockInList(employee?.clockNo, settings.enabledClockNos);
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
  if (ModuleClaims.instance.uiIsInkStaff == true) return true;
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
