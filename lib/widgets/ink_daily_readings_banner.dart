import 'package:flutter/material.dart';

import '../models/ink_daily_readings_status.dart';
import '../screens/ink_daily_readings_screen.dart';

/// Home / Ink hub reminder when today's combined readings are incomplete.
class InkDailyReadingsBanner extends StatelessWidget {
  const InkDailyReadingsBanner({super.key, required this.status});

  final InkDailyReadingsStatus status;

  // Ink group colour — matches the indigo Ink Factory / Daily Readings tiles
  // on Home. Flat colour-tinted style (wash + border) like those tiles, so
  // the reminder reads as part of the Ink group rather than an error state.
  static const Color _ink = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    if (status.complete) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _ink.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _ink.withValues(alpha: 0.45), width: 0.8),
      ),
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
              const Icon(Icons.speed, color: _ink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status.bannerMessage,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: _ink),
            ],
          ),
        ),
      ),
    );
  }
}