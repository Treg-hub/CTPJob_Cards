import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Manager-only reminder: GRN receipt packs ready to forward from Pulse.
class InkStoresPackBanner extends StatelessWidget {
  const InkStoresPackBanner({
    super.key,
    required this.readyCount,
    this.pulseUrl = 'https://ctp-pulse.web.app/ink/ordering?tab=grn',
  });

  final int readyCount;
  final String pulseUrl;

  static const Color _ink = kInkModule;

  Future<void> _openPulse(BuildContext context) async {
    final uri = Uri.parse(pulseUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open CTP Pulse.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (readyCount <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _ink.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _ink.withValues(alpha: 0.45), width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openPulse(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: _ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readyCount == 1
                          ? 'Stock received — action to be taken on Pulse'
                          : 'Stock received ($readyCount) — action to be taken on Pulse',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Open Pulse → Ordering → GRN receipts',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: _ink, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
