import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app Waste Recovery guide — loads [docs/waste_user_guide.md].
/// When [embedded] is true, renders without a Scaffold for the Waste home tabs.
class WasteGuideScreen extends StatefulWidget {
  const WasteGuideScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<WasteGuideScreen> createState() => _WasteGuideScreenState();
}

class _WasteGuideScreenState extends State<WasteGuideScreen> {
  static const _assetPath = 'docs/waste_user_guide.md';

  String? _markdown;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = await rootBundle.loadString(_assetPath);
      if (mounted) setState(() { _markdown = content; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _markdown = null; });
    }
  }

  Future<void> _openLink(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load the guide.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _error = null; _markdown = null; });
                _load();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_markdown == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Markdown(
      data: _markdown!,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        h1: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
        h2: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
        h3: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
        p: Theme.of(context).textTheme.bodyMedium,
        tableBorder: TableBorder.all(color: Theme.of(context).dividerColor),
        tableHead: const TextStyle(fontWeight: FontWeight.bold),
        tableCellsPadding: const EdgeInsets.all(6),
        blockquoteDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 4,
            ),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      onTapLink: (text, href, title) {
        if (href != null) _openLink(href);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Waste Recovery Guide')),
      body: body,
    );
  }
}