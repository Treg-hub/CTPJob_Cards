import 'package:flutter/material.dart';

import '../models/ink_daily_readings_status.dart';
import '../screens/ink_daily_readings_screen.dart';

/// Home / Ink hub reminder when today's combined readings are incomplete.
class InkDailyReadingsBanner extends StatelessWidget {
  const InkDailyReadingsBanner({super.key, required this.status});

  final InkDailyReadingsStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.complete) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InkDailyReadingsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.speed, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status.bannerMessage,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}