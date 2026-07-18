import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Shared open ink-count-period strip for Lurgi history surfaces.
class LurgiPeriodBanner extends StatelessWidget {
  const LurgiPeriodBanner({
    super.key,
    required this.periodFrom,
    this.settingsLoading = false,
  });

  final DateTime? periodFrom;
  final bool settingsLoading;

  static final _day = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;
    final scheme = Theme.of(context).colorScheme;
    final String text;
    if (settingsLoading) {
      text = 'Loading ink count period…';
    } else if (periodFrom == null) {
      text =
          'No active month-end count on file — period lists stay empty until a count exists. Closed periods: CTP Pulse.';
    } else {
      text =
          'Open ink count period since ${_day.format(periodFrom!)}. Closed periods: CTP Pulse.';
    }
    return Card(
      margin: EdgeInsets.zero,
      color: appColors.lurgiSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: appColors.lurgiDark.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: periodFrom == null && !settingsLoading
                    ? scheme.onSurface
                    : appColors.lurgiDark,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
