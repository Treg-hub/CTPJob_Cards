import '../models/employee.dart';
import '../models/fleet_settings.dart';
import '../models/waste_settings.dart';
import 'role.dart';

/// First-run onboarding track. Specialized floor roles get a shorter path
/// focused on their module; classic job-card roles keep the full tour.
enum OnboardingPersona {
  securityGuard,
  securityManager,
  fleetMechanic,
  fleetReporter,
  inkFloor,
  jobCards,
}

/// Pure persona pick for onboarding (unit-testable). Order is intentional:
/// exclusive shells / allow-lists first, then ink floor (non-admin), else job cards.
OnboardingPersona resolveOnboardingPersona(
  Employee? employee, {
  WasteSettings? wasteSettings,
  FleetSettings? fleetSettings,
}) {
  if (employee == null) return OnboardingPersona.jobCards;

  // Registry admins configure the whole plant — full job-card tour.
  if (isAdmin(employee)) return OnboardingPersona.jobCards;

  // Manager before guard: isSecurityGuard() is true for managers too.
  if (isSecurityManager(employee, wasteSettings)) {
    return OnboardingPersona.securityManager;
  }
  if (isSecurityGuard(employee, wasteSettings)) {
    return OnboardingPersona.securityGuard;
  }
  if (isFleetMechanic(employee, fleetSettings)) {
    return OnboardingPersona.fleetMechanic;
  }
  if (isFleetReporter(employee, fleetSettings) &&
      roleFromEmployee(employee) == UserRole.operator) {
    // Pure floor reporters: short fleet path. Managers who also report keep
    // the full job-card tour.
    return OnboardingPersona.fleetReporter;
  }
  if (isInkUser(employee)) {
    return OnboardingPersona.inkFloor;
  }
  return OnboardingPersona.jobCards;
}

/// Home tiles / tabs the user should expect after onboarding (plain language).
List<String> onboardingHomeExpectations(OnboardingPersona persona) {
  return switch (persona) {
    OnboardingPersona.securityGuard => const [
        'Site Security tab — vehicle and visitor gate flows',
        'Waste Recovery tab — Begin Collection on scheduled loads',
        'Notification inbox for parked alerts when off site',
      ],
    OnboardingPersona.securityManager => const [
        'Site Security and Waste tabs for gate + collections',
        'Full job-card Home tools (create, my work, manager views as applicable)',
        'Weighbridge / cost review stays on CTP Pulse, not mobile',
      ],
    OnboardingPersona.fleetMechanic => const [
        'Fleet tab — open issues and mark-fixed / work records',
        'Job cards still available for plant faults',
        'No cost amounts on mobile (cost manager handles that)',
      ],
    OnboardingPersona.fleetReporter => const [
        'Fleet daily check and report-issue actions',
        'Create Job Card for plant faults',
        'On-site status for alerts and presence',
      ],
    OnboardingPersona.inkFloor => const [
        'Ink Factory tab — stock, IBC, daily readings as applicable',
        'Create Job Card when something breaks on the plant',
        'Manager costing / month-end on CTP Pulse',
      ],
    OnboardingPersona.jobCards => const [
        'Create Job Card and My Work',
        'Priority alerts while you are on site',
        'Module tabs (Waste / Fleet / Ink / Security) only if your role uses them',
      ],
  };
}

/// Roles that should not lightly skip core alert permissions.
bool onboardingStrictCorePermissions(OnboardingPersona persona, Employee? emp) {
  if (persona == OnboardingPersona.jobCards) {
    final role = roleFromEmployee(emp);
    return role == UserRole.technician || role == UserRole.manager;
  }
  // Guards and fleet mechanics also depend on notifications / location.
  return persona == OnboardingPersona.securityGuard ||
      persona == OnboardingPersona.fleetMechanic;
}
