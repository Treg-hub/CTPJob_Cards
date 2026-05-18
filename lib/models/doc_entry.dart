import 'package:flutter/material.dart';
import '../utils/role.dart';

/// A documentation file bundled with the app, surfaced via the Settings →
/// Documentation entry. The `id` matches the .md filename in `docs/` (without
/// the extension). `roles` is the set of user roles allowed to see this doc;
/// `requiresAdmin` flips the entry to admin-only regardless of role.
class DocEntry {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Set<UserRole> roles;
  final bool requiresAdmin;

  const DocEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.roles,
    this.requiresAdmin = false,
  });

  String get assetPath => 'docs/$id.md';
}
