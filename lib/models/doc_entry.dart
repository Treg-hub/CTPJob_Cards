import 'package:flutter/material.dart';
import '../utils/role.dart';

/// A documentation file bundled with the app, surfaced via the Settings →
/// Documentation entry. The `id` matches the .md filename in `docs/` (without
/// the extension).
///
/// Access gates (checked in order in `docsForUser()`):
/// - `requiresAdmin` — Admin-only, regardless of role.
/// - `requiresWaste` — WasteTrack users only (Security Manager, Security Guard,
///   Admin). Non-waste employees cannot see this doc even if their base role
///   matches `roles`.
/// - `requiresFleet` — Fleet Maintenance users only (Mechanic, Reporter, Cost
///   Manager, Admin). Gated on the same condition as the Fleet tab.
/// - `requiresSecurity` — Site Security users only (guard, manager, Admin).
///   Further narrowed per-doc in `docsForUser` (guard vs manager guides).
/// - `roles` — Set of base [UserRole]s allowed to see this doc.
class DocEntry {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Set<UserRole> roles;
  final bool requiresAdmin;

  /// When true, only employees for whom `isWasteUser()` returns true can see
  /// this doc. Use for WasteTrack-specific guides that are not relevant to
  /// general job-card users (technicians, operators from other departments).
  final bool requiresWaste;

  /// When true, only Fleet users (mechanic, reporter, cost manager, admin) can
  /// see this doc, and only when the Fleet module is enabled. Mirrors the
  /// visibility of the Fleet tab itself.
  final bool requiresFleet;

  /// When true, only employees for whom `canUseSecurityModule()` returns true
  /// can see this doc (when Site Security is enabled). Use for Site Security
  /// guides; guard-only vs manager-only docs are filtered in `docsForUser`.
  final bool requiresSecurity;

  const DocEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.roles,
    this.requiresAdmin = false,
    this.requiresWaste = false,
    this.requiresFleet = false,
    this.requiresSecurity = false,
  });

  String get assetPath => 'docs/$id.md';
}
