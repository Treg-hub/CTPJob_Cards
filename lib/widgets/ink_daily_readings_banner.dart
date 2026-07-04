import 'package:flutter/material.dart';

import '../models/ink_daily_readings_status.dart';
import '../screens/ink_daily_readings_screen.dart';
import '../theme/app_theme.dart';

/// Home / Ink hub reminder when today's combined readings are incomplete.
class InkDailyReadingsBanner extends StatelessWidget {
  const InkDailyReadingsBanner({super.key, required this.status});

  final InkDailyReadingsStatus status;

  // Ink group colour — matches Ink Factory / Daily Readings tiles on Home.
  static const Color _ink = kInkModule;

  @override
  Widget build(BuildContext context) {
    if (status.complete) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _ink.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _ink.withValues(alpha: 0.45), width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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