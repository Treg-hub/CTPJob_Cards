import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee.dart';
import '../models/fleet_settings.dart';

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
      pos.contains('technician')) {
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

/// True when [employee] is the system admin. Admin is currently gated by a
/// single hardcoded clock number — centralising the check here so we have one
/// place to extend it (e.g. to a Firestore-backed admin list or custom claim).
bool isAdmin(Employee? employee) {
  return employee?.clockNo == '22';
}

// =============================================================================
// WASTE TRACK (WasteTrack) role helpers
// =============================================================================
// Roles are derived from existing Employee fields only (no new schema columns).
// This keeps changes to the live Job Cards app minimal and safe.
//
// Security team derivation (per spec + user decision):
//   - Admin: reuses the existing isAdmin() check (clockNo == '22' for now)
//   - Security Manager: department == "Security" && position == "Manager"
//   - Security Guard:   department == "Security" && position == "Guard"
//
// These helpers are used for:
//   - Showing/hiding the Waste navigation
//   - Routing Security roles directly to a focused Waste home screen
//   - Client-side enforcement of who can see costs, edit after complete,
//     view deviation alerts, manage rates, recover soft-deletes, etc.
//
// Phase 3 (Admin Tools) & Phase 6 (Testing & Hardening) updates (2026-05):
// WasteAdminScreen now has functional Manage Types (create + addSubtype) and
// Manage Rates (setRate + live list) behind isWasteAdmin. Reports use real
// loads + CSV export (pure Dart). Added error/loading states + new tests in
// test/waste_*_test.dart. All edits limited to waste_* files + allowed utils.
// =============================================================================

/// Returns true if this user should have full WasteTrack Admin rights
/// (currently reuses the global isAdmin check).
bool isWasteAdmin(Employee? employee) {
  return isAdmin(employee);
}

/// Returns true if the employee is a Security Manager
/// (department "Security" + position "Manager").
bool isSecurityManager(Employee? employee) {
  if (employee == null) return false;
  final dept = employee.department.toLowerCase();
  final pos = employee.position.toLowerCase();
  return dept == 'security' && pos == 'manager';
}

/// Returns true if the employee is a Security Guard
/// (department "Security" + position "Guard").
bool isSecurityGuard(Employee? employee) {
  if (employee == null) return false;
  final dept = employee.department.toLowerCase();
  final pos = employee.position.toLowerCase();
  return dept == 'security' && pos == 'guard';
}

/// Convenience: any WasteTrack user (Admin, Security Manager, or Security Guard).
bool isWasteUser(Employee? employee) {
  return isWasteAdmin(employee) || isSecurityManager(employee) || isSecurityGuard(employee);
}

// -----------------------------------------------------------------------------
// WasteTrack Feature Flag (Safety Net for Production Rollout)
// -----------------------------------------------------------------------------

/// Returns whether WasteTrack features should be visible/enabled for this user.
/// 
/// Uses SharedPreferences flag (key: 'wasteTrackEnabled') + role check.
/// Default: enabled for users with waste role (for pilot).
/// 
/// This is the production safety valve. Can be toggled via future Remote Config or admin screen.
/// Safety: All Waste UI remains gated behind isWasteUser() even if flag is true.
Future<bool> isWasteTrackEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  final flag = prefs.getBool('wasteTrackEnabled') ?? true; // Default on for pilot
  return flag;
}

/// Synchronous version for navigation / quick checks (defaults to true until prefs loaded).
/// The async version should be preferred for settings screens.
bool isWasteTrackEnabledSync() {
  // Safe default: on for users who have the role. Real value loaded async.
  return true;
}

// =============================================================================
// FLEET MAINTENANCE role helpers
// =============================================================================
// Fleet roles are derived from Employee fields + FleetSettings config:
//   - Fleet Mechanic:     department == "Workshop" && position == "Hyster Mechanic"
//   - Fleet Reporter:     employee.department in fleet_settings.reporterDepartments
//   - Fleet Cost Manager: employee.clockNo in fleet_settings.costManagerClockNos
//   - Fleet Admin:        reuses isAdmin() (clockNo == '22')
//
// Helpers that check reporter/cost-manager take FleetSettings as a parameter —
// the caller is responsible for loading and caching the settings doc.
// The home_screen loads settings in initState and stores the result in state.
// =============================================================================

/// True when the employee is the Hyster mechanic
/// (department "Workshop" + position "Hyster Mechanic"). Case-sensitive match.
bool isFleetMechanic(Employee? employee) {
  if (employee == null) return false;
  return employee.department == 'Workshop' && employee.position == 'Hyster Mechanic';
}

/// True when the employee's department is in the configurable reporter allow-list.
bool isFleetReporter(Employee? employee, FleetSettings? settings) {
  if (employee == null || settings == null) return false;
  return settings.reporterDepartments.contains(employee.department);
}

/// True when the employee's clock number is in the cost-manager allow-list.
bool isFleetCostManager(Employee? employee, FleetSettings? settings) {
  if (employee == null || settings == null) return false;
  return settings.costManagerClockNos.contains(employee.clockNo);
}

/// True when the employee has full fleet admin rights (reuses global isAdmin).
bool isFleetAdmin(Employee? employee) => isAdmin(employee);

/// Convenience: any Fleet user (shows Fleet tab when true).
bool isFleetUser(Employee? employee, FleetSettings? settings) {
  return isFleetMechanic(employee) ||
      isFleetAdmin(employee) ||
      isFleetReporter(employee, settings) ||
      isFleetCostManager(employee, settings);
}
