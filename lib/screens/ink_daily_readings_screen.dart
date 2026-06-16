import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ink_provider.dart';
import 'ink_meter_point_entry_screen.dart';
import 'ink_meter_readings_grid_screen.dart';

/// Daily Readings hub — entry point for Lurgi (and Ink Factory during transition).
/// Shows the done/due status for both the ink-meter and toloul-meter sessions,
/// locked once completed for the calendar day. Target time: 06:00 daily.
class InkDailyReadingsScreen extends ConsumerWidget {
  const InkDailyReadingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inkDone =
        ref.watch(inkTodayInkMeterDoneProvider).valueOrNull ?? false;
    final toloulDone =
        ref.watch(inkTodayToloulMeterDoneProvider).valueOrNull ?? false;
    final inkLoading = ref.watch(inkTodayInkMeterDoneProvider).isLoading;
    final toloulLoading =
        ref.watch(inkTodayToloulMeterDoneProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Readings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TargetBanner(),
          const SizedBox(height: 20),
          _ReadingCard(
            title: 'Ink Meters',
            subtitle: 'Yellow · Red · Blue · Black · Gravure Binder',
            icon: Icons.speed_outlined,
            done: inkDone,
            loading: inkLoading,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const InkMeterReadingsGridScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ReadingCard(
            title: 'Toloul Meters',
            subtitle: 'Recovery · Usage meter points',
            icon: Icons.opacity_outlined,
            done: toloulDone,
            loading: toloulLoading,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const InkMeterPointEntryScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.schedule, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily target: 06:00',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold)),
              Text('Enter both readings each morning',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.done,
    required this.loading,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool done;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: done ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: done
                      ? scheme.surfaceContainerHighest
                      : scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: done
                      ? scheme.onSurfaceVariant
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: done
                                    ? scheme.onSurfaceVariant
                                    : null)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    if (loading)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else if (done)
                      Row(
                        children: [
                          Icon(Icons.check_circle,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary),
                          const SizedBox(width: 4),
                          Text('Done today',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.w600)),
                        ],
                      )
                    else
                      Text('Due — tap to enter',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (!done && !loading)
                Icon(Icons.chevron_right,
                    color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
