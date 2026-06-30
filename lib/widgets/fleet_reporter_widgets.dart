import 'package:flutter/material.dart';

import '../models/fleet_issue.dart';
import '../theme/app_theme.dart';

/// Plain-language severity labels for reporters.
String reporterSeverityLabel(FleetIssueSeverity severity) {
  switch (severity) {
    case FleetIssueSeverity.low:
      return 'Minor';
    case FleetIssueSeverity.medium:
      return 'Normal';
    case FleetIssueSeverity.high:
      return 'Urgent';
    case FleetIssueSeverity.outOfService:
      return 'Out of service';
  }
}

String reporterSeverityHint(FleetIssueSeverity severity) {
  switch (severity) {
    case FleetIssueSeverity.low:
      return 'Small fault — machine can still be used.';
    case FleetIssueSeverity.medium:
      return 'Needs attention soon — machine can still work for now.';
    case FleetIssueSeverity.high:
      return 'Serious fault — mechanic should prioritise this.';
    case FleetIssueSeverity.outOfService:
      return 'Machine cannot be used until fixed. The mechanic is notified straight away.';
  }
}

class FleetReporterGuideBanner extends StatelessWidget {
  const FleetReporterGuideBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_problem_outlined, color: kBrandOrange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tap the machine, tap how urgent, then describe the problem. '
              'Or use Report Problem on the home screen for a shortcut.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// All urgency levels with plain-language hints (step 2 — nothing selected yet).
class FleetReporterSeverityOptionsGuide extends StatelessWidget {
  const FleetReporterSeverityOptionsGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.appColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < FleetIssueSeverity.values.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _SeverityGuideRow(severity: FleetIssueSeverity.values[i]),
        ],
        const SizedBox(height: 4),
        Text(
          'Tap an option above to continue.',
          style: TextStyle(fontSize: 12, color: muted, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _SeverityGuideRow extends StatelessWidget {
  const _SeverityGuideRow({required this.severity});

  final FleetIssueSeverity severity;

  @override
  Widget build(BuildContext context) {
    final isOos = severity == FleetIssueSeverity.outOfService;
    final accent = isOos ? Colors.red.shade800 : kBrandOrange;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isOos ? Icons.warning_amber_rounded : Icons.circle,
          size: isOos ? 16 : 8,
          color: accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: 13,
                    height: 1.35,
                    color: isOos ? Colors.red.shade900 : null,
                  ),
              children: [
                TextSpan(
                  text: '${reporterSeverityLabel(severity)} — ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: reporterSeverityHint(severity)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class FleetReporterSeverityHint extends StatelessWidget {
  const FleetReporterSeverityHint({super.key, required this.severity});

  final FleetIssueSeverity severity;

  @override
  Widget build(BuildContext context) {
    final isOos = severity == FleetIssueSeverity.outOfService;
    final bg = isOos ? Colors.red.shade50 : kBrandOrange.withValues(alpha: 0.06);
    final border =
        isOos ? Colors.red.shade300 : kBrandOrange.withValues(alpha: 0.3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isOos ? Icons.warning_amber_rounded : Icons.info_outline,
            color: isOos ? Colors.red : kBrandOrange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reporterSeverityHint(severity),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isOos ? Colors.red.shade900 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}