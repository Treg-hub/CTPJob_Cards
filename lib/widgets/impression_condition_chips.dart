import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Chip picker + optional free text when "Other" is selected.
/// [value] is either a chip label or free text when Other is active.
class ImpressionConditionChips extends StatefulWidget {
  const ImpressionConditionChips({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  /// Impression roller surface / defect conditions (daily IR).
  static const List<String> rollerOptions = [
    'OK',
    'Uneven surface',
    'Delaminated',
    'Swollen rubber',
    'Burst rubber',
    'Cracks',
    'Damaged A side',
    'Dirty',
    'Other',
  ];

  /// ESA charge / pressure-roller path conditions.
  static const List<String> esaChargeOptions = [
    'OK',
    'Working',
    'Dirty',
    'Damaged',
    'Not working',
    'Missing',
    'Other',
  ];

  /// ESA discharge bar conditions.
  static const List<String> esaDischargeOptions = [
    'OK',
    'Working',
    'Dirty',
    'Damaged',
    'Not working',
    'Missing',
    'Other',
  ];

  @override
  State<ImpressionConditionChips> createState() =>
      _ImpressionConditionChipsState();
}

class _ImpressionConditionChipsState extends State<ImpressionConditionChips> {
  late TextEditingController _otherCtrl;
  bool _other = false;

  @override
  void initState() {
    super.initState();
    final isKnown = widget.options.contains(widget.value) &&
        widget.value != 'Other' &&
        widget.value.isNotEmpty;
    _other = widget.value.isNotEmpty && !isKnown;
    _otherCtrl = TextEditingController(text: _other ? widget.value : '');
  }

  @override
  void didUpdateWidget(covariant ImpressionConditionChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final isKnown = widget.options.contains(widget.value) &&
          widget.value != 'Other' &&
          widget.value.isNotEmpty;
      _other = widget.value.isNotEmpty && !isKnown;
      if (_other && _otherCtrl.text != widget.value) {
        _otherCtrl.text = widget.value;
      }
    }
  }

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _select(String opt) {
    if (opt == 'Other') {
      setState(() => _other = true);
      widget.onChanged(_otherCtrl.text.trim());
    } else {
      setState(() => _other = false);
      widget.onChanged(opt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _other
        ? 'Other'
        : (widget.options.contains(widget.value) ? widget.value : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: widget.options.map((opt) {
            final isSelected = selected == opt;
            return FilterChip(
              label: Text(
                opt,
                style: TextStyle(
                  color: isSelected ? Colors.black : scheme.onSurface,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => _select(opt),
              selectedColor: kBrandOrange.withValues(alpha: 0.35),
              checkmarkColor: Colors.black,
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide(
                color: isSelected
                    ? kBrandOrange
                    : scheme.outline.withValues(alpha: 0.5),
              ),
            );
          }).toList(),
        ),
        if (_other) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _otherCtrl,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Describe condition',
              labelStyle: TextStyle(color: scheme.onSurfaceVariant),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ],
    );
  }
}
