import 'package:flutter/material.dart';
import '../models/doc_entry.dart';
import '../models/employee.dart';
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
    id: 'cloud_functions_deployment',
    title: 'Cloud Functions Deployment',
    description: 'Function inventory, regions, deployment commands.',
    icon: Icons.cloud,
    roles: {UserRole.admin},
    requiresAdmin: true,
  ),
  DocEntry(
    id: 'firebase_security_rules',
    title: 'Firebase Security Rules',
    description: 'Access control — what rules enforce and what to tighten.',
    icon: Icons.lock_outline,
    roles: {UserRole.admin},
    requiresAdmin: true,
  ),
];

/// Returns the docs visible to [employee] given their inferred role plus
/// admin status. Admin-only docs are filtered out for non-admin users.
List<DocEntry> docsForUser(Employee? employee) {
  final role = roleFromEmployee(employee);
  final admin = isAdmin(employee);
  return docCatalog.where((doc) {
    if (doc.requiresAdmin && !admin) return false;
    if (admin) return true;
    return doc.roles.contains(role);
  }).toList(growable: false);
}
