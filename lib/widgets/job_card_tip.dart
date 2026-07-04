import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/job_card_tips_provider.dart';

/// Wraps a guidance tip on the Create Job Card screen so it can be hidden
/// globally via [jobCardTipsVisibleProvider]. When [dismissible] is true a
/// small close button is overlaid; tapping it hides ALL job-card tips (they're
/// re-enabled from Settings → Preferences).
class JobCardTip extends ConsumerWidget {
  const JobCardTip({super.key, required this.child, this.dismissible = false});

  final Widget child;
  final bool dismissible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(jobCardTipsVisibleProvider);
    if (!visible) return const SizedBox.shrink();
    if (!dismissible) return child;
    // passthrough so the tip fills the parent's width (a stretch Column gives
    // tight width constraints); the default loose fit made the Stack — and so
    // the tip — shrink to its text content.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          top: -4,
          right: -4,
          child: IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Hide tips (turn back on in Settings)',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              ref.read(jobCardTipsVisibleProvider.notifier).setVisible(false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Tips hidden — turn back on in Settings > Preferences'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
