import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../main.dart' show currentEmployee;
import '../models/press_manual_entry.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/press_manuals_access_service.dart';
import '../services/secure_screen_service.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/ctp_app_bar.dart';

/// In-app OEM PDF viewer — private file only, FLAG_SECURE, no share/export.
class PressManualPdfViewerScreen extends StatefulWidget {
  final PressManualEntry entry;
  final File file;

  const PressManualPdfViewerScreen({
    super.key,
    required this.entry,
    required this.file,
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
    // pdfrx PdfTextSearcher.addListener returns an unsubscribe callback.
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

  @override
  Widget build(BuildContext context) {
    if (!_gateReady) {
      return const Scaffold(
        appBar: CtpAppBar(title: 'Press manuals'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_allowed) {
      return Scaffold(
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: const Center(child: Text('Access denied.')),
      );
    }

    final searcher = _searcher;

    return Scaffold(
      appBar: CtpAppBar(
        title: widget.entry.title,
        actions: [
          IconButton(
            tooltip: 'Find in document',
            icon: const Icon(Icons.search),
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
                      'In-app only · Downloaded to private app storage · '
                      'No share/export. CTP confidential.',
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
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Find text in this PDF…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _runSearch,
                        onChanged: (v) {
                          if (v.isEmpty) _runSearch('');
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _runSearch(_searchCtrl.text),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: _matchCount == 0
                          ? null
                          : () => searcher?.goToPrevMatch(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: _matchCount == 0
                          ? null
                          : () => searcher?.goToNextMatch(),
                    ),
                    if (_matchCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('$_matchIndex/$_matchCount'),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: PdfViewer.file(
              widget.file.path,
              controller: _controller,
              params: PdfViewerParams(
                backgroundColor: Theme.of(context).colorScheme.surface,
                pagePaintCallbacks: [
                  if (searcher != null) searcher.pageTextMatchPaintCallback,
                ],
                linkHandlerParams: PdfLinkHandlerParams(
                  onLinkTap: (_) {
                    // Swallow external links — stay inside the app.
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
