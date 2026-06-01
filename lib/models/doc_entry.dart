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

  const DocEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.roles,
    this.requiresAdmin = false,
    this.requiresWaste = false,
  });

  String get assetPath => 'docs/$id.md';
}
