import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../main.dart' show currentEmployee;
import '../models/press_manual_entry.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/press_manuals_access_service.dart';
import '../services/secure_screen_service.dart';
import '../theme/app_theme.dart';
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

  String _highlightedMarkdown(String body, String q) {
    if (q.trim().isEmpty) return body;
    final re = RegExp(RegExp.escape(q.trim()), caseSensitive: false);
    return body.replaceAllMapped(re, (m) => '**⟦${m[0]}⟧**');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    if (!_gateReady) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!role_utils.canAccessPressManuals(currentEmployee, _access)) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Access denied. isAdmin, allowlisted clocks, or Pressroom / '
              'technicians when enabled by an admin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ),
      );
    }

    final q = _searchCtrl.text;
    final matches = _markdown == null ? 0 : _matchCount(_markdown!, q);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: CtpAppBar(
        title: widget.entry.title,
        actions: [
          IconButton(
            tooltip: 'Find in pack',
            icon: const Icon(Icons.search, color: Colors.white),
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
          if (_showSearch)
            Material(
              color: scheme.surfaceContainerHighest,
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(color: scheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Find text in this pack…',
                          hintStyle: TextStyle(color: appColors.textMuted),
                          isDense: true,
                          filled: true,
                          fillColor: appColors.inputFill,
                          border: const OutlineInputBorder(),
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
                            color: matches == 0
                                ? scheme.error
                                : scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody(context, q, scheme, appColors)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String q,
    ColorScheme scheme,
    AppColors appColors,
  ) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(
                "Couldn't load this pack.",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: appColors.textMuted),
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
    final onSurf = scheme.onSurface;
    final muted = appColors.textMuted;
    final accent = scheme.brightness == Brightness.dark
        ? const Color(0xFF5EEAD4)
        : const Color(0xFF0F766E);

    return Markdown(
      controller: _scrollCtrl,
      data: data,
      padding: ScreenInsets.symmetricScroll(context),
      selectable: false,
      onTapLink: (text, href, title) {},
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: onSurf,
            ),
        h2: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: onSurf,
            ),
        h3: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: onSurf,
            ),
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onSurf),
        listBullet: TextStyle(color: onSurf),
        strong: TextStyle(fontWeight: FontWeight.bold, color: onSurf),
        em: TextStyle(fontStyle: FontStyle.italic, color: onSurf),
        a: TextStyle(color: scheme.primary),
        tableBody: TextStyle(color: onSurf),
        tableHead: TextStyle(fontWeight: FontWeight.bold, color: onSurf),
        tableBorder: TableBorder.all(color: scheme.outlineVariant),
        tableCellsPadding: const EdgeInsets.all(6),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          border: Border(left: BorderSide(color: accent, width: 4)),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquote: TextStyle(color: onSurf),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: onSurf,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        // Keep body readable; muted only for secondary if needed.
        del: TextStyle(color: muted, decoration: TextDecoration.lineThrough),
      ),
    );
  }
}
