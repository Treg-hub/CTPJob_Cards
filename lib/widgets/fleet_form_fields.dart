import 'package:flutter/material.dart';

/// Max items shown inline before switching to a searchable bottom sheet.
const int kFleetDropdownThreshold = 12;

/// Shared outline decoration for fleet dropdowns and form fields.
InputDecoration fleetDropdownDecoration({
  String? hintText,
  String? labelText,
  bool isDense = false,
  String? errorText,
}) {
  return InputDecoration(
    border: const OutlineInputBorder(),
    isDense: isDense,
    hintText: hintText,
    labelText: labelText,
    errorText: errorText,
  );
}

/// Section label used above fleet form fields.
class FleetSectionLabel extends StatelessWidget {
  const FleetSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Compact placeholder while a fleet selector loads its options.
class FleetDropdownLoading extends StatelessWidget {
  const FleetDropdownLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 48,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}