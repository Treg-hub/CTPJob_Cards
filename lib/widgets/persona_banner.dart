import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/persona_provider.dart';

/// Amber banner shown while an admin is testing as another employee (UI persona).
class PersonaBanner extends ConsumerWidget {
  const PersonaBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaProvider);
    if (!persona.isActive || persona.employee == null) {
      return const SizedBox.shrink();
    }

    final emp = persona.employee!;
    final writes = persona.allowTestSubmissions ? 'writes on' : 'view only';

    return Material(
      color: Colors.amber.shade100,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.science_outlined,
                  size: 18, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Testing as ${emp.name} (${emp.department} · ${emp.position}) — $writes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                    height: 1.3,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(personaProvider.notifier).stop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.amber.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Stop'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}