import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../main.dart' show currentEmployee;
import '../models/press_manual_entry.dart';
import '../models/press_manuals_access_settings.dart';
import '../services/press_manual_cache_service.dart';
import '../services/press_manuals_access_service.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import 'press_manual_pdf_viewer_screen.dart';
import 'press_manual_viewer_screen.dart';

/// Press manuals hub: short packs (bundled) + OEM chapters (download on open).
class PressManualsScreen extends StatefulWidget {
  const PressManualsScreen({super.key});

  @override
  State<PressManualsScreen> createState() => _PressManualsScreenState();
}

class _PressManualsScreenState extends State<PressManualsScreen> {
  static const Color _accent = Color(0xFF0D9488);

  final _cache = PressManualCacheService();
  final _searchCtrl = TextEditingController();
  final Map<String, bool> _cached = {};
  String? _downloadingId;
  double _downloadProgress = 0;
  PressManualsAccessSettings _access = PressManualsAccessSettings.defaults;
  bool _accessLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAccess();
    _refreshCacheFlags();
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

    // Remote PDF: download to private cache if needed, then in-app viewer.
    final already = _cached[entry.id] == true;
    if (!already) {
      final sizeHint = entry.sizeLabel.isEmpty ? '' : ' (${entry.sizeLabel})';
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download for in-app use?'),
          content: Text(
            '“${entry.title}” will download into private app storage only.\n\n'
            'It is not saved to Downloads, not shared, and only opens inside '
            'Job Cards.$sizeHint\n\n'
            'Wi‑Fi recommended for large chapters.',
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

  @override
  Widget build(BuildContext context) {
    if (!_accessLoaded) {
      return const Scaffold(
        appBar: CtpAppBar(title: 'Press manuals'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_canAccess) {
      return Scaffold(
        appBar: const CtpAppBar(title: 'Press manuals'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Press manuals are only available to isAdmin users, or to '
              'Pressroom / technicians when an admin enables those switches '
              'under Factory Admin → Modules.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final q = _searchCtrl.text;
    final filtered = pressManualCatalog.where((e) => e.matchesQuery(q)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final sections = <String, List<PressManualEntry>>{};
    for (final e in filtered) {
      sections.putIfAbsent(e.section, () => []).add(e);
    }
    const sectionOrder = ['short_packs', 'aurora_oem', 'badenia_oem'];

    return Scaffold(
      appBar: const CtpAppBar(title: 'Press manuals'),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          Card(
            color: _accent.withValues(alpha: 0.12),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, color: _accent, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'In-app only',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Short packs are on the phone. Full OEM chapters download only '
                    'when you open them, into private app storage — not Downloads, '
                    'not shareable outside Job Cards.\n\n'
                    'Use the search box to find a title; open a document and use '
                    'the search icon to find text inside it.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search manuals by name or topic…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
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
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No manuals match that search.')),
            )
          else
            ...sectionOrder.where(sections.containsKey).expand((sectionId) {
              final items = sections[sectionId]!;
              return [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    pressManualSectionTitle(sectionId),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                ...items.map(_tile),
              ];
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _tile(PressManualEntry entry) {
    final downloading = _downloadingId == entry.id;
    final onDevice = entry.isBundledMarkdown || _cached[entry.id] == true;

    String subtitle;
    if (entry.isBundledMarkdown) {
      subtitle = '${entry.press} · On device · ${entry.description}';
    } else if (downloading) {
      final pct = (_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
      subtitle = 'Downloading… $pct%';
    } else if (onDevice) {
      subtitle =
          '${entry.press} · Saved in app${entry.sizeLabel.isEmpty ? '' : ' · ${entry.sizeLabel}'} · ${entry.description}';
    } else {
      subtitle =
          '${entry.press} · Tap to download${entry.sizeLabel.isEmpty ? '' : ' · ${entry.sizeLabel}'} · ${entry.description}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _accent.withValues(alpha: 0.15),
          child: downloading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    color: _accent,
                  ),
                )
              : Icon(
                  onDevice && entry.isRemotePdf
                      ? Icons.offline_pin_outlined
                      : entry.icon,
                  color: _accent,
                  size: 22,
                ),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: entry.isRemotePdf && onDevice && !downloading
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'remove') _removeCache(entry);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from this device'),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right),
        onTap: downloading ? null : () => _open(entry),
      ),
    );
  }
}
