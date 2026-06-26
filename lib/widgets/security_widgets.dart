import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/security_gate.dart';
import '../providers/security_provider.dart';
import '../theme/app_theme.dart';

class SecurityGateSelector extends ConsumerWidget {
  const SecurityGateSelector({
    super.key,
    required this.onChanged,
    this.label = 'Gate',
  });

  final ValueChanged<SecurityGate?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gatesAsync = ref.watch(securityGatesProvider);
    final selected = ref.watch(selectedSecurityGateProvider);

    return gatesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Failed to load gates: $e'),
      data: (gates) {
        if (gates.isEmpty) {
          return const Text('No gates configured. Ask an admin to seed security_gates.');
        }
        return DropdownButtonFormField<SecurityGate>(
          value: selected ?? (gates.length == 1 ? gates.first : null),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: gates
              .map((g) => DropdownMenuItem(value: g, child: Text(g.name)))
              .toList(),
          onChanged: (gate) {
            ref.read(selectedSecurityGateProvider.notifier).state = gate;
            onChanged(gate);
          },
        );
      },
    );
  }
}

class SecurityActionCard extends StatelessWidget {
  const SecurityActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: enabled
          ? kBrandOrange.withValues(alpha: 0.08)
          : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: enabled
              ? kBrandOrange.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    enabled ? kBrandOrange : scheme.surfaceContainerHigh,
                child: Icon(
                  icon,
                  color: enabled ? Colors.white : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: enabled ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}