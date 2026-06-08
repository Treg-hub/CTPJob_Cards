import 'package:flutter/material.dart';

import 'fleet_form_fields.dart';

/// One option in a fleet filter dropdown (e.g. asset name, work type).
class FleetFilterOption<T> {
  const FleetFilterOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Compact filter dropdown with a shared fleet outline style.
class FleetFilterDropdown<T> extends StatelessWidget {
  const FleetFilterDropdown({
    super.key,
    required this.labelText,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allValue,
  });

  final String labelText;
  final String allLabel;
  final T? value;
  final T? allValue;
  final List<FleetFilterOption<T>> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T?>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: fleetDropdownDecoration(
        labelText: labelText,
        isDense: true,
      ),
      items: [
        DropdownMenuItem<T?>(value: allValue, child: Text(allLabel)),
        ...options.map(
          (option) => DropdownMenuItem<T?>(
            value: option.value,
            child: Text(
              option.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}