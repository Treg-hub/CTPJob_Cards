import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';

/// One-shot Press Live viewer (`press_live/current`). Refresh only — no listener.
class PressLiveScreen extends StatefulWidget {
  const PressLiveScreen({super.key});

  @override
  State<PressLiveScreen> createState() => _PressLiveScreenState();
}

class _PressLiveScreenState extends State<PressLiveScreen> {
  static const _docPath = 'press_live/current';
  static const _order = ['wifag', 'badenia', 'aurora'];
  static const _staleAfter = Duration(minutes: 15);

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  DateTime? _fetchedAt;
  /// All presses start collapsed; ids here are expanded.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance.doc(_docPath).get();
      if (!mounted) return;
      if (!snap.exists || snap.data() == null) {
        setState(() {
          _data = null;
          _loading = false;
          _fetchedAt = DateTime.now();
          _error = 'No press snapshot yet. Bridge may not be running.';
        });
        return;
      }
      setState(() {
        _data = snap.data();
        _loading = false;
        _fetchedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  DateTime? get _polledAt {
    final polled = _data?['polledAt'] ?? _data?['lastSuccessAt'];
    if (polled is Timestamp) return polled.toDate();
    return null;
  }

  Duration? get _age {
    final t = _polledAt ?? _fetchedAt;
    if (t == null) return null;
    return DateTime.now().difference(t);
  }

  bool get _isStale {
    final age = _age;
    return age != null && age > _staleAfter;
  }

  /// App-bar subtitle / title trailing: last update age or clock time.
  String _appBarUpdateLabel() {
    final age = _age;
    final t = _polledAt ?? _fetchedAt;
    if (age == null || t == null) return 'Not loaded';
    if (age.inMinutes < 1) return 'Updated just now';
    if (age.inMinutes < 60) return 'Updated ${age.inMinutes}m ago';
    return 'Updated ${DateFormat('HH:mm').format(t)}';
  }

  Color _toneColor(String? tone, String? status, ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final fromStatus = (status ?? '').toLowerCase();
    // Dark theme uses brighter accents — green-800 / amber-700 wash out on
    // near-black cards (dark-on-dark).
    if (tone == 'good' || fromStatus.contains('good copy')) {
      return dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    }
    if (tone == 'bad' || fromStatus.contains('bad copy')) {
      return dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    }
    if (tone == 'idle' ||
        fromStatus.contains('waiting') ||
        fromStatus.contains('idle')) {
      return dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
    }
    if (tone == 'warn') {
      return dark ? const Color(0xFFFB923C) : const Color(0xFFC2410C);
    }
    return dark ? scheme.onSurfaceVariant : scheme.outline;
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v : num.tryParse(v.toString().replaceAll(',', ''));
    if (n == null) return v.toString();
    final f = NumberFormat('#,###');
    if (n == n.roundToDouble()) return f.format(n.round());
    return n.toString();
  }

  String _duration(dynamic min) {
    if (min is! num) return '';
    final m = min.round();
    final h = m ~/ 60;
    final r = m % 60;
    if (h > 0) return '$h:${r.toString().padLeft(2, '0')}';
    return '0:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    final scheme = Theme.of(context).colorScheme;
    final presses = (_data?['presses'] as Map?)?.cast<String, dynamic>() ?? {};
    final updateLabel = _appBarUpdateLabel();

    return Scaffold(
      // Match Job Cards chrome (brand orange + on-site gradient). The previous
      // flat scheme.surface AppBar was dark-on-dark against scaffold #000.
      appBar: CtpAppBar(
        title: 'Press Live',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                updateLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  // Black/dark on orange bar — not muted white (was unreadable
                  // intent on the old dark AppBar; stale stays high-contrast).
                  color: _isStale
                      ? const Color(0xFF7C2D12)
                      : Colors.black.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: _loading && _data != null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _data == null
          ? Center(
              child: CircularProgressIndicator(color: scheme.primary),
            )
          : RefreshIndicator(
              color: scheme.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: ScreenInsets.symmetricScroll(context),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                  ],
                  for (final id in _order)
                    if (presses[id] is Map) ...[
                      Builder(
                        builder: (context) {
                          final data =
                              Map<String, dynamic>.from(presses[id] as Map);
                          final tone = _toneColor(
                            data['statusTone']?.toString(),
                            data['status']?.toString(),
                            scheme,
                          );
                          final expanded = _expanded.contains(id);
                          return _PressCard(
                            data: data,
                            toneColor: tone,
                            fmtNum: _fmtNum,
                            duration: _duration,
                            expanded: expanded,
                            onToggle: () => setState(() {
                              if (expanded) {
                                _expanded.remove(id);
                              } else {
                                _expanded.add(id);
                              }
                            }),
                          );
                        },
                      ),
                    ],
                  if (presses.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No press rows in snapshot.',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Pull down or tap refresh',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

class _PressCard extends StatelessWidget {
  const _PressCard({
    required this.data,
    required this.toneColor,
    required this.fmtNum,
    required this.duration,
    required this.expanded,
    required this.onToggle,
  });

  final Map<String, dynamic> data;
  final Color toneColor;
  final String Function(dynamic) fmtNum;
  final String Function(dynamic) duration;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final name = (data['pressName'] ?? data['pressId'] ?? 'Press').toString();
    final status = (data['status'] ?? '—').toString();
    final dur = duration(data['statusDurationMin']);
    final jobId = data['jobId']?.toString();
    final jobName = data['jobName']?.toString();
    final pct = data['progressPct'];
    final pctVal = pct is num ? (pct.clamp(0, 100) / 100.0) : 0.0;
    final op = data['operatorName']?.toString();
    final statusLabel = dur.isEmpty ? status : '$status · $dur';
    // Elevate slightly above pure-black scaffold (#000) — cardSurface alone
    // (#1A1A1A) reads as dark-on-dark without a stroke.
    final cardBg = scheme.brightness == Brightness.dark
        ? const Color(0xFF242424)
        : Theme.of(context).appColors.cardSurface;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.55 : 0.35,
          ),
        ),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.35,
                        color: onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: toneColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: toneColor.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: toneColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: muted,
                  ),
                ],
              ),
              if ((jobName != null && jobName.isNotEmpty) ||
                  (jobId != null && jobId.isNotEmpty)) ...[
                const SizedBox(height: 8),
                Text(
                  (jobName != null && jobName.isNotEmpty) ? jobName : jobId!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                if (expanded &&
                    jobName != null &&
                    jobName.isNotEmpty &&
                    jobId != null &&
                    jobId.isNotEmpty)
                  Text(
                    jobId,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pctVal,
                        minHeight: 8,
                        backgroundColor: onSurface.withValues(alpha: 0.14),
                        color: toneColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pct is num ? '${pct.round()}%' : '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: toneColor,
                    ),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Act',
                        value: fmtNum(data['speedActual']),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Avg',
                        value: fmtNum(data['speedAvg']),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Plan',
                        value: fmtNum(data['speedPlan']),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'ME',
                        value: '${fmtNum(data['mePct'])}%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Copies ${fmtNum(data['unitsDone'])} / ${fmtNum(data['unitsTarget'])}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 6),
                Text(
                  'Plan ${data['plannedEndAt'] ?? '—'} · '
                  'ETA ${data['estimatedEndAt'] ?? '—'}'
                  '${op != null && op.isNotEmpty ? ' · $op' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: muted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
      ],
    );
  }
}
