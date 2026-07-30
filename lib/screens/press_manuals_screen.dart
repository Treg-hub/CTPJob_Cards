import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee;
import '../models/press_manual_entry.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/press_manual_cache_service.dart';
import '../services/press_manuals_access_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import 'press_manual_pdf_viewer_screen.dart';
import 'press_manual_viewer_screen.dart';

/// Press manuals hub: tab per press/equipment; short packs + on-demand OEM.
class PressManualsScreen extends StatefulWidget {
  const PressManualsScreen({super.key});

  @override
  State<PressManualsScreen> createState() => _PressManualsScreenState();
}

class _PressManualsScreenState extends State<PressManualsScreen>
    with SingleTickerProviderStateMixin {
  static const _hintPrefKey = 'press_manuals_library_hint_dismissed';

  final _cache = PressManualCacheService();
  final _searchCtrl = TextEditingController();
  final Map<String, bool> _cached = {};
  String? _downloadingId;
  double _downloadProgress = 0;
  PressManualsAccessSettings _access = PressManualsAccessSettings.defaults;
  bool _accessLoaded = false;
  bool _hintDismissed = true; // hide until prefs load (avoids flash)
  bool _hintPrefsLoaded = false;

  TabController? _tabController;
  List<PressManualTab> _tabs = const [];

  Color _accent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFF5EEAD4)
        : const Color(0xFF0F766E);
  }

  @override
  void initState() {
    super.initState();
    _tabs = buildPressManualTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadAccess();
    _loadHintPref();
    _refreshCacheFlags();
  }

  Future<void> _loadHintPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hintDismissed = prefs.getBool(_hintPrefKey) ?? false;
      _hintPrefsLoaded = true;
    });
  }

  Future<void> _dismissHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintPrefKey, true);
    if (mounted) setState(() => _hintDismissed = true);
  }

  Future<void> _loadAccess() async {
    try {
      final s = await PressManualsAccessService().getSettings();
      if (mounted) {
        setState(() {
          _access = s;
          _accessLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _accessLoaded = true);
    }
  }

  bool get _canAccess =>
      role_utils.canAccessPressManuals(currentEmployee, _access);

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _refreshCacheFlags() async {
    final map = <String, bool>{};
    for (final e in pressManualCatalog) {
      if (e.isRemotePdf) {
        map[e.id] = await _cache.isCached(e);
      }
    }
    if (mounted) setState(() => _cached.addAll(map));
  }

  Future<void> _open(PressManualEntry entry) async {
    if (!_canAccess) return;

    if (entry.isBundledMarkdown) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PressManualViewerScreen(entry: entry),
        ),
      );
      return;
    }

    final already = _cached[entry.id] == true;
    if (!already) {
      final sizeHint = entry.sizeLabel.isEmpty ? '' : ' (${entry.sizeLabel})';
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download for in-app use?'),
          content: Text(
            '“${entry.title}” will download into private app storage only.\n\n'
            'Wi‑Fi recommended for large chapters.$sizeHint',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Download & open'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _downloadingId = entry.id;
      _downloadProgress = already ? 1 : 0;
    });

    try {
      final file = await _cache.ensureLocal(
        entry,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _cached[entry.id] = true;
        _downloadingId = null;
      });
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PressManualPdfViewerScreen(entry: entry, file: file),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _downloadingId = null);
      final msg = e.code == 'object-not-found'
          ? 'This manual is not on the server yet. Ask an admin to upload '
              'press manuals to Storage (press_manuals/…).'
          : e.code == 'unauthorized'
              ? 'Not allowed to download. Check isAdmin or admin toggles '
                  '(Pressroom / technicians) and refresh your login claims.'
              : 'Download failed: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _removeCache(PressManualEntry entry) async {
    await _cache.removeLocal(entry);
    if (mounted) setState(() => _cached[entry.id] = false);
  }

  List<PressManualEntry> _entriesForTab(PressManualTab tab, String q) {
    return pressManualCatalog
        .where((e) => tab.matches(e) && e.matchesQuery(q))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    final accent = _accent(context);
    final tabController = _tabController;

    if (!_accessLoaded || tabController == null) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_canAccess) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Press manuals are only available to isAdmin users, or to '
              'Pressroom / technicians when an admin enables those switches '
              'under Factory Admin → Modules.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ),
      );
    }

    final q = _searchCtrl.text;

    // Tabs live on [scheme.surface] below CtpAppBar (not on the orange
    // gradient), same pattern as Factory Admin — keeps label/indicator colours
    // from fighting AppBar white foreground inheritance.
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: const CtpAppBar(title: 'Press manuals'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: scheme.surface,
            elevation: 0,
            child: TabBar(
              controller: tabController,
              isScrollable: _tabs.length > 3,
              tabAlignment:
                  _tabs.length > 3 ? TabAlignment.start : TabAlignment.fill,
              // Match global TabBarTheme + Admin: brand orange selected, muted unselected.
              labelColor: kBrandOrange,
              unselectedLabelColor: appColors.textMuted,
              indicatorColor: kBrandOrange,
              dividerColor: scheme.outlineVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: [
                for (final t in _tabs) Tab(text: t.label),
              ],
            ),
          ),
          Padding(
            padding: ScreenInsets.symmetricScroll(context).copyWith(
              top: 12,
              bottom: 0,
            ),
            child: Column(
              children: [
                if (_hintPrefsLoaded && !_hintDismissed) ...[
                  _HintCard(
                    scheme: scheme,
                    appColors: appColors,
                    onDismiss: _dismissHint,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search this press…',
                    hintStyle: TextStyle(color: appColors.textMuted),
                    prefixIcon: Icon(Icons.search, color: appColors.textMuted),
                    filled: true,
                    fillColor: appColors.inputFill,
                    suffixIcon: q.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.clear, color: appColors.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                for (final tab in _tabs)
                  _PressTabBody(
                    tab: tab,
                    entries: _entriesForTab(tab, q),
                    accent: accent,
                    scheme: scheme,
                    appColors: appColors,
                    downloadingId: _downloadingId,
                    downloadProgress: _downloadProgress,
                    cached: _cached,
                    onOpen: _open,
                    onRemoveCache: _removeCache,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final ColorScheme scheme;
  final AppColors appColors;
  final VoidCallback onDismiss;

  const _HintCard({
    required this.scheme,
    required this.appColors,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: scheme.onPrimaryContainer,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pick a press tab for its packs and handbooks. Short packs open '
                'straight away; larger OEM files download when you open them. '
                'Use search to filter the current tab.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _PressTabBody extends StatelessWidget {
  final PressManualTab tab;
  final List<PressManualEntry> entries;
  final Color accent;
  final ColorScheme scheme;
  final AppColors appColors;
  final String? downloadingId;
  final double downloadProgress;
  final Map<String, bool> cached;
  final Future<void> Function(PressManualEntry) onOpen;
  final Future<void> Function(PressManualEntry) onRemoveCache;

  const _PressTabBody({
    required this.tab,
    required this.entries,
    required this.accent,
    required this.scheme,
    required this.appColors,
    required this.downloadingId,
    required this.downloadProgress,
    required this.cached,
    required this.onOpen,
    required this.onRemoveCache,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No documents for ${tab.label} match your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: appColors.textMuted),
          ),
        ),
      );
    }

    final bySection = <String, List<PressManualEntry>>{};
    for (final e in entries) {
      bySection.putIfAbsent(e.section, () => []).add(e);
    }
    final sectionOrder = pressManualSectionOrderFor(entries);

    return ListView(
      padding: ScreenInsets.symmetricScroll(context).copyWith(top: 8),
      children: [
        for (final sectionId in sectionOrder) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              pressManualSectionTitle(sectionId),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: scheme.onSurface,
              ),
            ),
          ),
          for (final e in bySection[sectionId]!)
            _ManualTile(
              entry: e,
              accent: accent,
              scheme: scheme,
              appColors: appColors,
              downloading: downloadingId == e.id,
              downloadProgress: downloadProgress,
              onDevice: e.isBundledMarkdown || cached[e.id] == true,
              onOpen: () => onOpen(e),
              onRemoveCache: e.isRemotePdf ? () => onRemoveCache(e) : null,
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ManualTile extends StatelessWidget {
  final PressManualEntry entry;
  final Color accent;
  final ColorScheme scheme;
  final AppColors appColors;
  final bool downloading;
  final double downloadProgress;
  final bool onDevice;
  final VoidCallback onOpen;
  final VoidCallback? onRemoveCache;

  const _ManualTile({
    required this.entry,
    required this.accent,
    required this.scheme,
    required this.appColors,
    required this.downloading,
    required this.downloadProgress,
    required this.onDevice,
    required this.onOpen,
    this.onRemoveCache,
  });

  @override
  Widget build(BuildContext context) {
    String subtitle;
    if (entry.isBundledMarkdown) {
      subtitle = 'On device · ${entry.description}';
    } else if (downloading) {
      final pct = (downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
      subtitle = 'Downloading… $pct%';
    } else if (onDevice) {
      subtitle =
          'Saved${entry.sizeLabel.isEmpty ? '' : ' · ${entry.sizeLabel}'} · ${entry.description}';
    } else {
      subtitle =
          'Tap to download${entry.sizeLabel.isEmpty ? '' : ' · ${entry.sizeLabel}'} · ${entry.description}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: appColors.cardSurface,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.18),
          child: downloading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: downloadProgress > 0 ? downloadProgress : null,
                    color: accent,
                  ),
                )
              : Icon(
                  onDevice && entry.isRemotePdf
                      ? Icons.offline_pin_outlined
                      : entry.icon,
                  color: accent,
                  size: 22,
                ),
        ),
        title: Text(
          entry.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: appColors.textMuted),
        ),
        trailing: entry.isRemotePdf && onDevice && !downloading && onRemoveCache != null
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                onSelected: (v) {
                  if (v == 'remove') onRemoveCache!();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from this device'),
                  ),
                ],
              )
            : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: downloading ? null : onOpen,
      ),
    );
  }
}
