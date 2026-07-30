import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../main.dart' show currentEmployee;
import '../models/press_manual_entry.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/press_manuals_access_service.dart';
import '../services/secure_screen_service.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';

/// In-app-only viewer for bundled short packs (markdown).
class PressManualViewerScreen extends StatefulWidget {
  final PressManualEntry entry;

  const PressManualViewerScreen({super.key, required this.entry});

  @override
  State<PressManualViewerScreen> createState() =>
      _PressManualViewerScreenState();
}

class _PressManualViewerScreenState extends State<PressManualViewerScreen> {
  String? _markdown;
  Object? _error;
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;
  final _scrollCtrl = ScrollController();
  PressManualsAccessSettings _access = PressManualsAccessSettings.defaults;
  bool _gateReady = false;

  @override
  void initState() {
    super.initState();
    SecureScreenService.enterSecure();
    _loadGateAndBody();
  }

  Future<void> _loadGateAndBody() async {
    try {
      _access = await PressManualsAccessService().getSettings();
    } catch (_) {}
    if (mounted) setState(() => _gateReady = true);
    if (role_utils.canAccessPressManuals(currentEmployee, _access)) {
      await _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    SecureScreenService.exitSecure();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final path = widget.entry.assetPath;
      if (path == null) {
        throw StateError('No asset for ${widget.entry.id}');
      }
      final content = await rootBundle.loadString(path);
      if (mounted) {
        setState(() {
          _markdown = content;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _markdown = null;
        });
      }
    }
  }

  int _matchCount(String body, String q) {
    if (q.trim().isEmpty) return 0;
    final lower = body.toLowerCase();
    final needle = q.trim().toLowerCase();
    var count = 0;
    var from = 0;
    while (true) {
      final i = lower.indexOf(needle, from);
      if (i < 0) break;
      count++;
      from = i + needle.length;
    }
    return count;
  }

  /// Highlight matches for find-in-page (still not selectable for copy-out).
  String _highlightedMarkdown(String body, String q) {
    if (q.trim().isEmpty) return body;
    // Markdown-safe-ish: wrap matches in bold+underline via HTML not available;
    // use a simple marker the user can see — replace case-insensitively.
    final re = RegExp(RegExp.escape(q.trim()), caseSensitive: false);
    return body.replaceAllMapped(re, (m) => '**⟦${m[0]}⟧**');
  }

  @override
  Widget build(BuildContext context) {
    if (!_gateReady) {
      return const Scaffold(
        appBar: CtpAppBar(title: 'Press manuals'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!role_utils.canAccessPressManuals(currentEmployee, _access)) {
      return Scaffold(
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Access denied. isAdmin, or Pressroom / technicians when enabled '
              'by an admin.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final q = _searchCtrl.text;
    final matches =
        _markdown == null ? 0 : _matchCount(_markdown!, q);

    return Scaffold(
      appBar: CtpAppBar(
        title: widget.entry.title,
        actions: [
          IconButton(
            tooltip: 'Find in pack',
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _searchCtrl.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: const Color(0xFF7F1D1D),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'In-app only · Do not share, screenshot for others, or export. '
                      'CTP confidential.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showSearch)
            Material(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Find text in this pack…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (q.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          matches == 0 ? 'No matches' : '$matches match(es)',
                          style: TextStyle(
                            color: matches == 0 ? Colors.red : Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody(context, q)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, String q) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                "Couldn't load this pack.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _markdown = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_markdown == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _highlightedMarkdown(_markdown!, q);

    return Markdown(
      controller: _scrollCtrl,
      data: data,
      padding: ScreenInsets.symmetricScroll(context),
      selectable: false,
      onTapLink: (text, href, title) {},
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        h1: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(fontWeight: FontWeight.bold),
        h2: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
        h3: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
        p: Theme.of(context).textTheme.bodyMedium,
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFFFFF3E6),
          border: const Border(
            left: BorderSide(color: Color(0xFF0D9488), width: 4),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        tableBorder: TableBorder.all(color: Theme.of(context).dividerColor),
        tableHead: const TextStyle(fontWeight: FontWeight.bold),
        tableCellsPadding: const EdgeInsets.all(6),
      ),
    );
  }
}
