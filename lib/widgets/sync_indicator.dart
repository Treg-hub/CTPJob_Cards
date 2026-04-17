import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sync_queue_item.dart';

final syncQueueProvider = StreamProvider<int>((ref) {
  try {
    final box = Hive.box<SyncQueueItem>('syncQueue');
    return box.watch().map((_) => box.length);
  } catch (e) {
    // Return empty stream if box is not available
    return Stream.value(0);
  }
});

class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(syncQueueProvider);

    return asyncValue.when(
      data: (queueLength) {
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
                'Syncing $queueLength change${queueLength == 1 ? '' : 's'}…',
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
