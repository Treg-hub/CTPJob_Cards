import 'package:flutter/material.dart';

/// Loud PASS / FAIL control. Defaults to FAIL (red). User must choose PASS (green).
///
/// Used on mechanical start-build and electrical test so a pass cannot be
/// submitted by accident from a default-on switch.
class ImpressionPassFailToggle extends StatelessWidget {
  const ImpressionPassFailToggle({
    super.key,
    required this.pass,
    required this.onChanged,
    this.title = 'Result',
    this.failHint = 'Defaults to FAIL — toggle PASS only when the check is good.',
    this.passHint = 'PASS selected — assembly can move to the next step.',
  });

  final bool pass;
  final ValueChanged<bool> onChanged;
  final String title;
  final String failHint;
  final String passHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failColor = scheme.error;
    const passColor = Color(0xFF2E7D32); // strong green, readable on dark/light
    final tint = pass
        ? passColor.withValues(alpha: 0.18)
        : failColor.withValues(alpha: 0.20);
    final border = pass ? passColor : failColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            pass ? passHint : failHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.85),
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ChoiceChip(
                  label: 'FAIL',
                  selected: !pass,
                  selectedColor: failColor,
                  icon: Icons.cancel_outlined,
                  onTap: () => onChanged(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChoiceChip(
                  label: 'PASS',
                  selected: pass,
                  selectedColor: passColor,
                  icon: Icons.check_circle_outline,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? selectedColor : scheme.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? selectedColor
                  : scheme.outline.withValues(alpha: 0.5),
              width: selected ? 0 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : scheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.6,
                  color: selected ? Colors.white : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
