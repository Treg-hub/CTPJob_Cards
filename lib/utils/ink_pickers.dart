import 'package:flutter/material.dart';

/// Picks a date AND time — Ink Factory timestamps carry an editable time
/// component (staff may adjust both). Returns null if the date step is
/// cancelled; keeps [initial]'s time if the time step is cancelled.
Future<DateTime?> pickInkDateTime(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 7)),
  );
  if (d == null) return null;
  if (!context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  final time = t ?? TimeOfDay.fromDateTime(initial);
  return DateTime(d.year, d.month, d.day, time.hour, time.minute);
}
