import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dept_request_tips_provider.dart';

/// Wraps a Dept Request guidance tip; dismissible hides all tips until
/// Settings → Preferences restores them.
class DeptRequestTip extends ConsumerWidget {
  const DeptRequestTip({super.key, required this.child, this.dismissible = false});

  final Widget child;
  final bool dismissible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(deptRequestTipsVisibleProvider);
    if (!visible) return const SizedBox.shrink();
    if (!dismissible) return child;
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
              ref.read(deptRequestTipsVisibleProvider.notifier).setVisible(false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Dept Request tips hidden — turn back on in Settings > Preferences',
                  ),
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
