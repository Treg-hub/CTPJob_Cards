import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/ink_expected_deliveries.dart';

/// Compact ETA + urgency chip for receive list tiles.
class InkEtaChip extends StatelessWidget {
  const InkEtaChip({super.key, required this.eta, this.now});

  final DateTime? eta;
  final DateTime? now;

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (eta == null) {
      return Text(
        'ETA —',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }

    final days = daysUntilEta(eta!, now: now);
    final inHorizon = etaInHorizon(eta!, now: now);
    final urgency = urgencyForDaysUntil(days);
    final dateLabel = _fmt.format(eta!.toLocal());
    final urgencyLabel =
        expectedUrgencyLabel(urgency, inDays: days > 1 ? days : null);

    Color bg;
    Color fg;
    if (urgency == InkExpectedUrgency.overdue) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else if (urgency == InkExpectedUrgency.today) {
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
    } else if (inHorizon) {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
    }

    final label = inHorizon
        ? 'ETA $dateLabel (est.) · $urgencyLabel'
        : 'ETA $dateLabel (est.)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
