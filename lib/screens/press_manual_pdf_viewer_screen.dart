import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../main.dart' show currentEmployee;
import '../models/press_manual_entry.dart';
import '../models/press_manual_pdf_source.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/press_manuals_access_service.dart';
import '../services/secure_screen_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/ctp_app_bar.dart';

/// In-app OEM PDF viewer — private file/bytes only, FLAG_SECURE on Android,
/// no share/export/external browser open.
class PressManualPdfViewerScreen extends StatefulWidget {
  final PressManualEntry entry;
  final PressManualPdfSource source;

  const PressManualPdfViewerScreen({
    super.key,
    required this.entry,
    required this.source,
  });

  @override
  State<PressManualPdfViewerScreen> createState() =>
      _PressManualPdfViewerScreenState();
}

class _PressManualPdfViewerScreenState
    extends State<PressManualPdfViewerScreen> {
  final _controller = PdfViewerController();
  PdfTextSearcher? _searcher;
  VoidCallback? _unsubSearcher;
  final _searchCtrl = TextEditingController();
  int _matchIndex = 0;
  int _matchCount = 0;
  bool _showSearch = false;
  bool _ready = false;
  PressManualsAccessSettings _access = PressManualsAccessSettings.defaults;
  bool _gateReady = false;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    SecureScreenService.enterSecure();
    _controller.addListener(_onController);
    _loadGate();
  }

  Future<void> _loadGate() async {
    try {
      _access = await PressManualsAccessService().getSettings();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _gateReady = true;
      _allowed =
          role_utils.canAccessPressManuals(currentEmployee, _access);
    });
  }

  void _onController() {
    if (!_controller.isReady || _searcher != null) return;
    final searcher = PdfTextSearcher(_controller);
    _unsubSearcher = searcher.addListener(_onSearchChanged);
    _searcher = searcher;
    if (mounted) setState(() => _ready = true);
  }

  void _onSearchChanged() {
    final s = _searcher;
    if (s == null || !mounted) return;
    setState(() {
      _matchCount = s.matches.length;
      _matchIndex =
          s.hasMatches && s.currentIndex != null ? s.currentIndex! + 1 : 0;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _unsubSearcher?.call();
    _searcher?.dispose();
    _controller.removeListener(_onController);
    SecureScreenService.exitSecure();
    super.dispose();
  }

  void _runSearch(String q) {
    final s = _searcher;
    if (s == null) return;
    if (q.trim().isEmpty) {
      s.resetTextSearch();
      setState(() {
        _matchCount = 0;
        _matchIndex = 0;
      });
      return;
    }
    s.startTextSearch(
      q.trim(),
      caseInsensitive: true,
      searchImmediately: true,
    );
  }

  Widget _buildPdfViewer(ColorScheme scheme, PdfTextSearcher? searcher) {
    final params = PdfViewerParams(
      backgroundColor: scheme.surface,
      pagePaintCallbacks: [
        if (searcher != null) searcher.pageTextMatchPaintCallback,
      ],
      linkHandlerParams: PdfLinkHandlerParams(
        onLinkTap: (_) {},
      ),
    );

    final src = widget.source;
    if (src.hasBytes) {
      return PdfViewer.data(
        src.bytes as Uint8List,
        sourceName: src.sourceName,
        controller: _controller,
        params: params,
      );
    }
    if (src.hasFile) {
      return PdfViewer.file(
        src.filePath!,
        controller: _controller,
        params: params,
      );
    }
    return Center(
      child: Text(
        'No PDF data.',
        style: TextStyle(color: scheme.onSurface),
      ),
    );
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
    if (!_allowed) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: Center(
          child: Text(
            'Access denied.',
            style: TextStyle(color: scheme.onSurface),
          ),
        ),
      );
    }

    final searcher = _searcher;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: CtpAppBar(
        title: widget.entry.title,
        actions: [
          IconButton(
            tooltip: 'Find in document',
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: !_ready
                ? null
                : () {
                    setState(() => _showSearch = !_showSearch);
                    if (!_showSearch) {
                      _searchCtrl.clear();
                      _searcher?.resetTextSearch();
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Material(
              color: scheme.surfaceContainerHighest,
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(color: scheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Find text in this PDF…',
                          hintStyle: TextStyle(color: appColors.textMuted),
                          isDense: true,
                          filled: true,
                          fillColor: appColors.inputFill,
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _runSearch,
                        onChanged: (v) {
                          if (v.isEmpty) _runSearch('');
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.search, color: scheme.onSurface),
                      onPressed: () => _runSearch(_searchCtrl.text),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_up,
                        color: _matchCount == 0
                            ? scheme.onSurface.withValues(alpha: 0.38)
                            : scheme.onSurface,
                      ),
                      onPressed: _matchCount == 0
                          ? null
                          : () => searcher?.goToPrevMatch(),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: _matchCount == 0
                            ? scheme.onSurface.withValues(alpha: 0.38)
                            : scheme.onSurface,
                      ),
                      onPressed: _matchCount == 0
                          ? null
                          : () => searcher?.goToNextMatch(),
                    ),
                    if (_matchCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '$_matchIndex/$_matchCount',
                          style: TextStyle(color: scheme.onSurface),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildPdfViewer(scheme, searcher)),
        ],
      ),
    );
  }
}
