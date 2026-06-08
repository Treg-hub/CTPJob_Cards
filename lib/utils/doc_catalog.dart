import 'package:flutter/material.dart';
import '../models/doc_entry.dart';
import '../models/employee.dart';
import '../models/fleet_settings.dart';
import '../models/waste_settings.dart';
import 'role.dart';

const _allUserFacingRoles = <UserRole>{
  UserRole.operator,
  UserRole.technician,
  UserRole.manager,
  UserRole.admin,
};

/// Canonical list of every doc bundled in the app. Order here is the order
/// shown in the Documentation list, so put the most-likely-tapped guides
/// at the top.
const List<DocEntry> docCatalog = [
  DocEntry(
    id: 'employee_guide',
    title: 'Employee Guide',
    description: 'Onboarding, permissions, job-card workflow, notifications.',
    icon: Icons.person_outline,
    roles: _allUserFacingRoles,
  ),
  DocEntry(
    id: 'manager_guide',
    title: 'Manager Guide',
    description: 'Dashboards, daily review, escalation oversight, quality.',
    icon: Icons.supervisor_account,
    roles: {UserRole.manager, UserRole.admin},
  ),
  DocEntry(
    id: 'executive_overview',
    title: 'Executive Overview',
    description: 'The system at a glance — for managers and execs.',
    icon: Icons.insights,
    roles: {UserRole.manager, UserRole.admin},
  ),
  DocEntry(
    id: 'app_features',
    title: 'App Features',
    description: 'Feature-by-feature reference for the whole app.',
    icon: Icons.apps,
    roles: _allUserFacingRoles,
  ),
  DocEntry(
    id: 'escalation_system',
    title: 'Escalation System',
    description: 'How the 4-stage escalation reaches the right people.',
    icon: Icons.priority_high,
    roles: {UserRole.technician, UserRole.manager, UserRole.admin},
  ),
  DocEntry(
    id: 'screens_reference',
    title: 'Screens Reference',
    description: 'Every screen in the app — what it does, who can see it.',
    icon: Icons.phone_android,
    roles: _allUserFacingRoles,
  ),
  DocEntry(
    id: 'troubleshooting',
    title: 'Troubleshooting & FAQ',
    description: 'Symptoms and fixes for the most common issues.',
    icon: Icons.help_outline,
    roles: _allUserFacingRoles,
  ),
  DocEntry(
    id: 'CHANGELOG',
    title: 'Changelog',
    description: "What's new and what's changed in recent releases.",
    icon: Icons.update,
    roles: _allUserFacingRoles,
  ),
  DocEntry(
    id: 'waste_user_guide',
    title: 'WasteTrack User Guide',
    description: 'Scheduling loads, collecting waste, weighbridge sign-off, reports.',
    icon: Icons.recycling,
    roles: _allUserFacingRoles,
    requiresWaste: true,
  ),
  DocEntry(
    id: 'fleet_user_guide',
    title: 'Fleet Maintenance User Guide',
    description: 'Reporting forklift/grab faults, logging work, costs, and reports.',
    icon: Icons.forklift,
    roles: _allUserFacingRoles,
    requiresFleet: true,
  ),
  DocEntry(
    id: 'fleet_mechanic_guide',
    title: 'Mechanic Guide',
    description: 'To Fix, Start job, Finish the fix, History, and Log other work.',
    icon: Icons.build_circle_outlined,
    roles: _allUserFacingRoles,
    requiresFleet: true,
  ),
  DocEntry(
    id: 'fleet_reporter_guide',
    title: 'Reporter Guide',
    description: 'How to report a problem and pick the right urgency.',
    icon: Icons.report_problem_outlined,
    roles: _allUserFacingRoles,
    requiresFleet: true,
  ),
  DocEntry(
    id: 'fleet_cost_manager_guide',
    title: 'Cost Manager Guide',
    description: 'Costs tab job queue, general cost, and spend reports.',
    icon: Icons.receipt_long_outlined,
    roles: _allUserFacingRoles,
    requiresFleet: true,
  ),
];

/// Returns the docs visible to [employee] given their inferred role,
/// admin status, waste access, and fleet access.
///
/// [fleetSettings] is needed to resolve the Fleet roles (reporter / cost
/// manager are config-driven) and whether the module is enabled. Pass the
/// session-cached settings; when null, Fleet docs are hidden for non-admins.
///
/// Gate order:
/// 1. `requiresAdmin` — immediately excluded if the user is not admin.
/// 2. Admin users bypass all further checks and see everything.
/// 3. `requiresWaste` — excluded if `isWasteUser()` is false, even if the
///    base role matches. This keeps WasteTrack-specific guides away from
///    general job-card users (mechanics, operators from other departments).
/// 4. `requiresFleet` — excluded unless the Fleet module is enabled and the
///    user is a Fleet user. Mirrors the visibility of the Fleet tab.
/// 5. `roles` — standard role membership check.
List<DocEntry> docsForUser(Employee? employee,
    [FleetSettings? fleetSettings, WasteSettings? wasteSettings]) {
  final role = roleFromEmployee(employee);
  final admin = isAdmin(employee);
  final wasteUser = isWasteUser(employee, wasteSettings);
  final fleetUser = (fleetSettings?.fleetEnabled ?? false) &&
      isFleetUser(employee, fleetSettings);
  return docCatalog.where((doc) {
    if (doc.requiresAdmin && !admin) return false;
    if (admin) return true;
    if (doc.requiresWaste && !wasteUser) return false;
    if (doc.requiresFleet && !fleetUser) return false;
    if (fleetUser && !_canSeeFleetRoleGuide(doc.id, employee, fleetSettings, admin)) {
      return false;
    }
    return doc.roles.contains(role);
  }).toList(growable: false);
}

bool _canSeeFleetRoleGuide(
  String docId,
  Employee? employee,
  FleetSettings? settings,
  bool admin,
) {
  switch (docId) {
    case 'fleet_mechanic_guide':
      return admin || isFleetMechanic(employee, settings);
    case 'fleet_reporter_guide':
      return admin || isFleetReporter(employee, settings);
    case 'fleet_cost_manager_guide':
      return admin || isFleetCostManager(employee, settings);
    default:
      return true;
  }
}
