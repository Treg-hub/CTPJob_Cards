---
name: new-screen
description: Scaffold a new Flutter screen for CTP Job Cards with correct ConsumerStatefulWidget boilerplate, role-check stub, and standard imports. Pass the screen name in PascalCase, e.g. /new-screen CopperAuditScreen
---

Create a new screen file at `lib/screens/{{name_snake}}.dart` using this exact pattern from the codebase:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../services/firestore_service.dart';
import '../utils/role.dart';

class {{ScreenName}} extends ConsumerStatefulWidget {
  const {{ScreenName}}({super.key});

  @override
  ConsumerState<{{ScreenName}}> createState() => _{{ScreenName}}State();
}

class _{{ScreenName}}State extends ConsumerState<{{ScreenName}}> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (currentEmployee == null) return;
    setState(() => _isLoading = true);
    try {
      // TODO: load data
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = roleFromEmployee(currentEmployee);

    // Role gate — adjust as needed per capability matrix in CLAUDE.md
    if (role == UserRole.operator) {
      return const Scaffold(
        body: Center(child: Text('Access denied')),
      );
    }

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('{{Title}}')),
      body: const Center(child: Text('TODO')),
    );
  }
}
```

Rules to follow when generating the file:
1. Replace `{{ScreenName}}` with the PascalCase name given by the user (e.g. `CopperAuditScreen`).
2. Replace `{{name_snake}}` with the snake_case filename (e.g. `copper_audit_screen`).
3. Replace `{{Title}}` with a human-readable title derived from the name.
4. Only import services actually needed — remove `FirestoreService` if the screen won't use Firestore.
5. Adjust the role gate to match the capability matrix in CLAUDE.md for what this screen should expose.
6. After creating the file, remind the user to add a route for the new screen wherever it should be navigated to.
