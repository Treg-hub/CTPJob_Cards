import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// Soft-update strip on Home — does not block navigation.
class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateCheckResult?>(
      valueListenable: UpdateService().softOffer,
      builder: (context, offer, _) {
        if (offer == null || !offer.hasUpdate || offer.forceUpdate) {
          return const SizedBox.shrink();
        }
        final label = offer.latestBuild.isEmpty
            ? offer.latestVersion
            : '${offer.latestVersion} (${offer.latestBuild})';
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: kBrandOrange.withValues(alpha: 0.18),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.system_update, color: kBrandOrange, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Update available · $label',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (offer.releaseNotes.trim().isNotEmpty)
                          Text(
                            offer.releaseNotes.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => UpdateService().dismissSoftOffer(),
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandOrange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () =>
                        UpdateService().presentUpdate(context, offer),
                    child: const Text('Update'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
