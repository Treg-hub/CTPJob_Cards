import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sync_queue_item.dart';

final syncQueueProvider = StreamProvider<int>((ref) {
  try {
    // Must match the box opened in main.dart — this watched the non-existent
    // 'syncQueue' box for months, so the banner never appeared at all.
    final box = Hive.box<SyncQueueItem>('sync_queue');
    // Emit the current length immediately; box.watch() only fires on changes,
    // so items queued before this widget built were invisible.
    Stream<int> lengths() async* {
      yield box.length;
      yield* box.watch().map((_) => box.length);
    }

    return lengths();
  } catch (e) {
    // Return empty stream if box is not available
    return Stream.value(0);
  }
});

/// Global offline-queue banner on Home. Also clears stale "still uploading"
/// snackbars when the queue drains to zero after a successful background sync.
class SyncIndicator extends ConsumerStatefulWidget {
  const SyncIndicator({super.key});

  @override
  ConsumerState<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends ConsumerState<SyncIndicator> {
  int _prevLength = -1;

  @override
  Widget build(BuildContext context) {
    final asyncValue = ref.watch(syncQueueProvider);

    return asyncValue.when(
      data: (queueLength) {
        if (_prevLength >= 0 && _prevLength > 0 && queueLength == 0) {
          // Queue fully drained — drop any lingering offline-save snackbars.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            messenger?.hideCurrentSnackBar();
            messenger?.showSnackBar(
              const SnackBar(
                content: Text('All queued changes synced'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          });
        }
        _prevLength = queueLength;

        if (queueLength == 0) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: Colors.orange,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$queueLength change${queueLength == 1 ? '' : 's'} waiting to sync…',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) {
        // Don't show error UI, just hide the indicator
        return const SizedBox.shrink();
      },
    );
  }
}
