import '../models/employee.dart';

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
  if (pos.contains('mechanical') || pos.contains('electrical')) return UserRole.technician;
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
