import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/doc_entry.dart';
import '../services/whats_new_service.dart';
import '../utils/screen_insets.dart';

class DocViewerScreen extends StatefulWidget {
  final DocEntry entry;
  const DocViewerScreen({super.key, required this.entry});

  @override
  State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  String? _markdown;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var content = await rootBundle.loadString(widget.entry.assetPath);
      // Floor-safe: never show admin/ops subsections from the bundled changelog.
      if (widget.entry.id == 'CHANGELOG') {
        content = WhatsNewService.stripAdminSections(content);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.title),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromRGBO(255, 140, 66, 1), Color.fromARGB(255, 124, 124, 124)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _buildBody(context),
    );
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
            const Text("Couldn't load this guide.", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_error.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () { setState(() { _error = null; _markdown = null; }); _load(); },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42), foregroundColor: Colors.white),
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
      padding: ScreenInsets.symmetricScroll(context),
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        h1: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        h2: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        h3: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        p: Theme.of(context).textTheme.bodyMedium,
        tableBorder: TableBorder.all(color: Theme.of(context).dividerColor),
        tableHead: const TextStyle(fontWeight: FontWeight.bold),
        tableCellsPadding: const EdgeInsets.all(6),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFFFFF3E6),
          border: const Border(left: BorderSide(color: Color(0xFFFF8C42), width: 4)),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquote: const TextStyle(color: Colors.black87),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
}
