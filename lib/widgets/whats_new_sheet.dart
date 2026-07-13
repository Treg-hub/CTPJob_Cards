import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../screens/doc_viewer_screen.dart';
import '../theme/app_theme.dart';
import '../utils/doc_catalog.dart';
import '../utils/screen_insets.dart';

/// Bottom sheet shown once after an app update with changelog entries since
/// the user's last seen build (full roll-up). See WhatsNewService.
Future<void> showWhatsNewSheet(
  BuildContext context, {
  required String markdown,
  required String versionLabel,
  int? sinceBuild,
  int entryCount = 1,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _WhatsNewSheet(
      markdown: markdown,
      versionLabel: versionLabel,
      sinceBuild: sinceBuild,
      entryCount: entryCount,
    ),
  );
}

class _WhatsNewSheet extends StatelessWidget {
  final String markdown;
  final String versionLabel;
  final int? sinceBuild;
  final int entryCount;

  const _WhatsNewSheet({
    required this.markdown,
    required this.versionLabel,
    this.sinceBuild,
    this.entryCount = 1,
  });

  void _openFullChangelog(BuildContext context) {
    Navigator.of(context).pop();
    final entry = docCatalog.firstWhere((d) => d.id == 'CHANGELOG');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocViewerScreen(entry: entry)),
    );
  }

  String get _subtitle {
    if (sinceBuild != null && entryCount > 1) {
      return 'Everything since build $sinceBuild · now $versionLabel';
    }
    if (entryCount > 1) {
      return '$entryCount updates · now $versionLabel';
    }
    return 'You updated to $versionLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.new_releases_outlined,
                    color: kBrandOrange, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's changed",
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: Markdown(
              controller: scrollController,
              data: markdown,
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + ScreenInsets.bottomSafe(context),
              ),
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                // The entry heading is an h2 in the changelog — render it as a
                // compact title since the sheet header already says "What's
                // changed".
                h2: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                h3: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: kBrandOrange),
                p: theme.textTheme.bodyMedium,
                listBullet: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          SafeBottomBar(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _openFullChangelog(context),
                  style: TextButton.styleFrom(foregroundColor: kBrandOrange),
                  child: const Text('Full changelog'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                  ),
                  child: const Text('Got it',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
