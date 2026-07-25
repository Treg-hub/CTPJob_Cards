import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ink_provider.dart';
import '../utils/screen_insets.dart';
import 'ink_capture_signed_rfo_screen.dart';

/// Manager queue: POs (import + local) awaiting signed RFO photo and/or Pastel numbers.
class InkSignedRfoQueueScreen extends ConsumerWidget {
  const InkSignedRfoQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inkSignedRfoQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Signed RFO')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No orders waiting for a signed RFO photo or Pastel numbers.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              ScreenInsets.scrollBottomFullScreen(context),
            ),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final po = list[i];
              final needsPhoto = po.status.needsSignedRfoCapture ||
                  (po.signedRfoPdfPath == null || po.signedRfoPdfPath!.isEmpty);
              final trackLabel = po.isLocalTrack ? 'Local' : 'Import';
              return Card(
                child: ListTile(
                  title: Text(po.pulseRef),
                  subtitle: Text(
                    '$trackLabel · ${po.supplierName}\n'
                    '${needsPhoto ? 'Capture signed RFO photo' : 'Enter Pastel numbers'}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InkCaptureSignedRfoScreen(order: po),
                      ),
                    );
                    ref.invalidate(inkSignedRfoQueueProvider);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
