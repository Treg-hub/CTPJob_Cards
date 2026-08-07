import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../models/employee.dart';
import '../models/impression_settings.dart';
import '../services/impression_service.dart';
import '../theme/app_theme.dart';
import '../utils/ink_pickers.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_tip_banner.dart';
import 'impression_cycle_detail_screen.dart';
import 'impression_daily_esa_screen.dart';
import 'impression_daily_ir_screen.dart';
import 'impression_electrical_screen.dart';
import 'impression_start_build_screen.dart';

/// Single hub: full visibility; actions greyed by role; banners + next step.
///
/// Presence: managers/admin may open off-site; floor roles (No1/No2/Foreman without
/// manager title, Mechanic, Electrician) must be on-site.
class ImpressionHubScreen extends StatefulWidget {
  const ImpressionHubScreen({super.key});

  @override
  State<ImpressionHubScreen> createState() => _ImpressionHubScreenState();
}

class _ImpressionHubScreenState extends State<ImpressionHubScreen>
    with SingleTickerProviderStateMixin {
  /// Floor order: Aurora, Badenia, Wifag (not alphabetical by code id).
  static const _pressOrder = ['aurora', 'badenia', 'wifag'];
  static const _prefsPressKey = 'impression_preferred_press';

  ImpressionSettings _settings = ImpressionSettings.defaults;
  String _pressId = 'aurora';
  bool? _irDoneToday;
  bool? _esaDoneToday;
  int _awaitingCount = 0;
  int _stripCount = 0;
  int _elecCount = 0;
  TabController? _tabController;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _pressOrder.length, vsync: this);
    _tabController!.addListener(_onTabChanged);
    ImpressionService.instance.watchSettings().listen((s) {
      if (mounted) setState(() => _settings = s);
    });
    _loadPressPref();
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController == null || _tabController!.indexIsChanging) return;
    final id = _pressOrder[_tabController!.index];
    if (id == _pressId) return;
    setState(() => _pressId = id);
    _savePressPref(id);
    _refreshCompliance();
    _refreshCounts();
  }

  Future<void> _loadPressPref() async {
    final prefs = await SharedPreferences.getInstance();
    final clock = currentEmployee?.clockNo ?? 'anon';
    final saved = prefs.getString('${_prefsPressKey}_$clock') ??
        prefs.getString(_prefsPressKey);
    final id = _pressOrder.contains(saved) ? saved! : 'aurora';
    final idx = _pressOrder.indexOf(id);
    if (mounted) {
      setState(() {
        _pressId = id;
        _prefsLoaded = true;
      });
      _tabController?.index = idx < 0 ? 0 : idx;
      _refreshCompliance();
      _refreshCounts();
    }
  }

  Future<void> _savePressPref(String pressId) async {
    final prefs = await SharedPreferences.getInstance();
    final clock = currentEmployee?.clockNo ?? 'anon';
    await prefs.setString('${_prefsPressKey}_$clock', pressId);
  }

  Employee? get _emp => currentEmployee;
  bool get _isOnSite => realEmployee?.isOnSite ?? true;
  bool get _canMech => isImpressionMechanical(_emp, _settings);
  bool get _canElec => isImpressionElectrical(_emp, _settings);
  bool get _canPress => isImpressionPressroom(_emp, _settings);

  Future<void> _refreshCompliance() async {
    final dateKey = ImpressionService.todayDateKey();
    final ir = await FirebaseFirestore.instance
        .collection(Collections.impressionDailyIr)
        .where('pressId', isEqualTo: _pressId)
        .where('dateKey', isEqualTo: dateKey)
        .limit(5)
        .get();
    final esa = await FirebaseFirestore.instance
        .collection(Collections.impressionDailyEsa)
        .where('pressId', isEqualTo: _pressId)
        .where('dateKey', isEqualTo: dateKey)
        .limit(5)
        .get();
    if (mounted) {
      setState(() {
        _irDoneToday = ir.docs.isNotEmpty;
        _esaDoneToday = esa.docs.isNotEmpty;
      });
    }
  }

  Future<void> _refreshCounts() async {
    final slots = await FirebaseFirestore.instance
        .collection(Collections.impressionUnitSlots)
        .where('pressId', isEqualTo: _pressId)
        .where('state', isEqualTo: 'awaiting_install')
        .get();
    final strip = await FirebaseFirestore.instance
        .collection(Collections.impressionCycles)
        .where('state', isEqualTo: 'removed_pending_strip')
        .limit(30)
        .get();
    final elec = await FirebaseFirestore.instance
        .collection(Collections.impressionCycles)
        .where('state', isEqualTo: 'awaiting_electrical')
        .limit(30)
        .get();
    if (mounted) {
      setState(() {
        _awaitingCount = slots.docs.length;
        _stripCount = strip.docs.length;
        _elecCount = elec.docs.length;
      });
    }
  }

  String get _nextStep {
    if (_canPress && _awaitingCount > 0) {
      return 'Install $_awaitingCount unit(s) awaiting roller';
    }
    if (_canPress && _irDoneToday != true) return 'Complete daily IR for $_pressId';
    if (_canPress && _esaDoneToday != true) return 'Complete daily ESA for $_pressId';
    if (_canMech && _stripCount > 0) return 'Strip $_stripCount roller(s)';
    if (_canElec && _elecCount > 0) return 'Test $_elecCount assembly(ies)';
    if (_canMech) return 'Start a new build when sleeves return';
    return 'All clear — review map and queues';
  }

  @override
  Widget build(BuildContext context) {
    if (!PresenceGating.canAccessImpressionRollersPresence(
      emp: _emp,
      isOnSite: _isOnSite,
    )) {
      return const OffSiteBlockedScreen(
        title: 'Imp Rollers',
        message: PresenceGating.offSiteImpressionMessage,
      );
    }
    if (!canAccessImpressionRollers(_emp, _settings)) {
      return Scaffold(
        appBar: const ImpressionAppBar(title: 'Imp Rollers'),
        body: const Center(child: Text('No access for your role.')),
      );
    }

    final presses = _settings.presses.isEmpty
        ? ImpressionSettings.defaults.presses
        : _settings.presses;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    if (!_prefsLoaded || _tabController == null) {
      return const Scaffold(
        appBar: ImpressionAppBar(title: 'Imp Rollers'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Match View Job Cards: CtpAppBar + body TabBar (theme tabBarTheme, no local colours).
    return Scaffold(
      appBar: CtpAppBar(
        title: 'Imp Rollers',
        isOnSite: _isOnSite,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refreshCompliance();
              _refreshCounts();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: false,
            tabs: _pressOrder
                .map((id) => Tab(text: presses[id]?.label ?? id))
                .toList(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ImpressionTipBanner(
                  tipId: 'hub',
                  text: ImpressionTipBanner.tips['hub']!,
                ),
                Card(
                  color: kBrandOrange.withValues(alpha: 0.12),
                  child: ListTile(
                    leading: const Icon(Icons.flag, color: kBrandOrange),
                    title: Text('Your next step', style: TextStyle(color: onSurface)),
                    subtitle: Text(_nextStep, style: TextStyle(color: onSurface)),
                  ),
                ),
                if (_irDoneToday == false)
                  Card(
                    color: scheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: Icon(Icons.warning_amber, color: scheme.error),
                      title: Text(
                        'IR outstanding today · ${presses[_pressId]?.label ?? _pressId}',
                        style: TextStyle(color: onSurface),
                      ),
                      trailing: _canPress
                          ? TextButton(onPressed: _openDailyIr, child: const Text('Do IR'))
                          : null,
                    ),
                  ),
                if (_esaDoneToday == false)
                  Card(
                    color: scheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: Icon(Icons.warning_amber, color: scheme.error),
                      title: Text(
                        'ESA outstanding today · ${presses[_pressId]?.label ?? _pressId}',
                        style: TextStyle(color: onSurface),
                      ),
                      trailing: _canPress
                          ? TextButton(onPressed: _openDailyEsa, child: const Text('Do ESA'))
                          : null,
                    ),
                  ),
                const SizedBox(height: 12),
                _section(
                  title: 'Press map',
                  child: _PressMap(
                    pressId: _pressId,
                    canAct: _canPress,
                    onUnitTap: (unitNo, data) => _openUnitSheet(unitNo, data),
                    onOpenCycle: (id) => _openCycle(id),
                  ),
                ),
                _section(
                  title: 'Spares (this press)',
                  child: _SpareList(
                    pressId: _pressId,
                    canInstall: _canPress,
                    onInstall: _canPress ? (id, esa) => _pickUnitAndInstall(id, esa) : null,
                    onOpen: _openCycle,
                  ),
                ),
                _tile(
                  title: 'Daily IR inspection',
                  subtitle: _irDoneToday == true ? 'Done today' : 'Required when press running',
                  enabled: _canPress,
                  onTap: _openDailyIr,
                ),
                _tile(
                  title: 'Daily ESA inspection',
                  subtitle: _esaDoneToday == true ? 'Done today' : 'Yellow units skipped',
                  enabled: _canPress,
                  onTap: _openDailyEsa,
                ),
                _tile(
                  title: 'Start build (Mechanical)',
                  subtitle: 'Shaft + sleeve/UNN + control sheet',
                  enabled: _canMech,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ImpressionStartBuildScreen(pressId: _pressId),
                      ),
                    );
                    _refreshCounts();
                  },
                ),
                _section(
                  title: 'Electrical queue',
                  child: _CycleQueue(
                    state: 'awaiting_electrical',
                    enabled: _canElec,
                    actionLabel: 'Test',
                    onAction: _canElec
                        ? (id, data) async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImpressionElectricalScreen(
                                  cycleId: id,
                                  cycleData: data,
                                ),
                              ),
                            );
                            _refreshCounts();
                          }
                        : null,
                    onOpen: _openCycle,
                  ),
                ),
                _section(
                  title: 'Electrical failed (quarantine)',
                  child: _CycleQueue(
                    state: 'electrical_fail',
                    enabled: _canElec || _canMech,
                    actionLabel: 'Retest',
                    onAction: _canElec
                        ? (id, data) async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImpressionElectricalScreen(
                                  cycleId: id,
                                  cycleData: data,
                                ),
                              ),
                            );
                          }
                        : null,
                    onOpen: _openCycle,
                  ),
                ),
                _section(
                  title: 'Strip queue',
                  child: _CycleQueue(
                    state: 'removed_pending_strip',
                    enabled: _canMech,
                    actionLabel: 'Strip',
                    onAction: _canMech ? _showStrip : null,
                    onOpen: _openCycle,
                  ),
                ),
                _section(
                  title: 'Send-out pending',
                  child: _CycleQueue(
                    state: 'sleeve_send_out_pending',
                    enabled: _canMech,
                    actionLabel: 'Send out',
                    onAction: _canMech ? _showSendOut : null,
                    onOpen: _openCycle,
                  ),
                ),
                _section(
                  title: 'At vendor',
                  child: _CycleQueue(
                    state: 'sleeve_at_vendor',
                    enabled: _canMech,
                    actionLabel: 'Receive',
                    onAction: _canMech
                        ? (id, _) async {
                            await ImpressionService.instance.receive(cycleId: id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Received — start new build')),
                            );
                            _refreshCounts();
                          }
                        : null,
                    onOpen: _openCycle,
                  ),
                ),
                _section(
                  title: 'Received sleeves (rebuild)',
                  child: _CycleQueue(
                    state: 'sleeve_received',
                    enabled: _canMech,
                    actionLabel: 'Rebuild',
                    onAction: _canMech
                        ? (id, data) async {
                            final shaft = data['shaftNo']?.toString() ?? '';
                            final sleeve = data['sleeveId']?.toString() ?? '';
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImpressionStartBuildScreen(pressId: _pressId),
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Use shaft $shaft / sleeve $sleeve')),
                            );
                          }
                        : null,
                    onOpen: _openCycle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: enabled,
        title: Text(title, style: TextStyle(color: onSurface)),
        subtitle: Text(
          enabled ? subtitle : '$subtitle · not your step',
          style: TextStyle(color: onSurface.withValues(alpha: 0.75)),
        ),
        trailing: Icon(
          enabled ? Icons.chevron_right : Icons.lock_outline,
          color: onSurface,
        ),
        onTap: enabled ? onTap : null,
      ),
    );
  }

  Future<void> _openDailyIr() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImpressionDailyIrScreen(
          pressId: _pressId,
          settings: _settings,
        ),
      ),
    );
    _refreshCompliance();
  }

  Future<void> _openDailyEsa() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImpressionDailyEsaScreen(
          pressId: _pressId,
          settings: _settings,
        ),
      ),
    );
    _refreshCompliance();
  }

  void _openCycle(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImpressionCycleDetailScreen(cycleId: id)),
    );
  }

  Future<void> _openUnitSheet(int unitNo, Map<String, dynamic> data) async {
    final state = data['state']?.toString() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Unit $unitNo', style: Theme.of(context).textTheme.titleLarge),
              Text('$state · ${data['shaftNo'] ?? "—"} / ${data['sleeveId'] ?? "—"}'),
              if (data['overMaxStreak'] != null)
                Text('Over-max streak: ${data['overMaxStreak']}'),
              const SizedBox(height: 12),
              if (data['cycleId'] != null)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Life review'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openCycle(data['cycleId'] as String);
                  },
                ),
              if (_canPress && state == 'occupied')
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRemove(unitNo: unitNo);
                  },
                  child: const Text('Remove roller'),
                ),
              if (_canPress && state == 'awaiting_install')
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickSpareAndInstall(unitNo);
                  },
                  child: const Text('Install from spares'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRemove({int? unitNo}) async {
    final unitCtrl = TextEditingController(text: '${unitNo ?? 1}');
    final revsCtrl = TextEditingController();
    String reason = _settings.removalReasons.isNotEmpty
        ? _settings.removalReasons.first
        : 'planned_change';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove roller'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit 1–8'),
              keyboardType: TextInputType.number,
            ),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: reason,
              items: (_settings.removalReasons.isEmpty
                      ? ['planned_change', 'other']
                      : _settings.removalReasons)
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => reason = v ?? reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            TextField(
              controller: revsCtrl,
              decoration: const InputDecoration(labelText: 'Revolutions (millions) *'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final unit = int.tryParse(unitCtrl.text) ?? 0;
    final revs = double.tryParse(revsCtrl.text);
    if (revs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter revolutions in millions')),
      );
      return;
    }
    try {
      await ImpressionService.instance.removeRoller(
        pressId: _pressId,
        unitNo: unit,
        reason: reason,
        revsMillions: revs,
      );
      if (!mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Removed'),
          content: const Text('Install a replacement from spares now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continue other work')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Install now')),
          ],
        ),
      );
      if (install == true && mounted) await _pickSpareAndInstall(unit);
      _refreshCounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _pickSpareAndInstall(int unitNo) async {
    final snaps = await FirebaseFirestore.instance
        .collection(Collections.impressionCycles)
        .where('state', isEqualTo: 'spare_ready')
        .where('pressId', isEqualTo: _pressId)
        .limit(30)
        .get();
    if (!mounted) return;
    if (snaps.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No spares for this press')),
      );
      return;
    }
    final chosen = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Select spare for unit $unitNo'),
        children: snaps.docs.map((d) {
          final m = d.data();
          final esa = m['esaSuitability'] ?? 'full';
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, d),
            child: Text('${m['shaftNo']} / ${m['sleeveId']} ($esa) · ${m['cycleNo']}'),
          );
        }).toList(),
      ),
    );
    if (chosen == null || !mounted) return;
    final m = chosen.data();
    await _installCycle(
      chosen.id,
      unitNo,
      m['esaSuitability']?.toString(),
      shaftNo: m['shaftNo']?.toString(),
      sleeveId: m['sleeveId']?.toString(),
      unitFixed: true,
    );
  }

  Future<void> _pickUnitAndInstall(String cycleId, String? esa) async {
    String? shaftNo;
    String? sleeveId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(Collections.impressionCycles)
          .doc(cycleId)
          .get();
      final m = snap.data();
      shaftNo = m?['shaftNo']?.toString();
      sleeveId = m?['sleeveId']?.toString();
    } catch (_) {}
    if (!mounted) return;
    await _installCycle(
      cycleId,
      1,
      esa,
      shaftNo: shaftNo,
      sleeveId: sleeveId,
      unitFixed: false,
    );
  }

  /// Confirm install: date/time (manager/admin editable) above shaft number, then unit.
  Future<void> _installCycle(
    String cycleId,
    int unitNo,
    String? esa, {
    String? shaftNo,
    String? sleeveId,
    bool unitFixed = true,
  }) async {
    final canEditTs = canEditImpressionTimestamp(currentEmployee);
    final unitCtrl = TextEditingController(text: '$unitNo');
    var effectiveAt = DateTime.now();
    final confirmed = await showDialog<_InstallConfirmResult>(
      context: context,
      builder: (ctx) {
        final df = DateFormat('EEE d MMM yyyy · HH:mm');
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickTs() async {
              if (!canEditTs) return;
              final dt = await pickInkDateTime(ctx, effectiveAt);
              if (dt != null) setLocal(() => effectiveAt = dt);
            }

            return AlertDialog(
              title: const Text('Install roller'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canEditTs)
                      OutlinedButton.icon(
                        onPressed: pickTs,
                        icon: const Icon(Icons.event),
                        label: Text('Date & time: ${df.format(effectiveAt)}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          alignment: Alignment.centerLeft,
                        ),
                      )
                    else
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date & time',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.event),
                        ),
                        child: Text(df.format(effectiveAt)),
                      ),
                    if (canEditTs)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          'Managers and admins can adjust the date and time.',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Shaft (Roller No.)',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        (shaftNo != null && shaftNo.isNotEmpty) ? shaftNo : '—',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Sleeve',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        (sleeveId != null && sleeveId.isNotEmpty) ? sleeveId : '—',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (unitFixed)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          border: OutlineInputBorder(),
                        ),
                        child: Text('$unitNo'),
                      )
                    else
                      TextField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Unit 1–8 *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final u = unitFixed
                        ? unitNo
                        : int.tryParse(unitCtrl.text.trim());
                    if (u == null || u < 1 || u > 8) return;
                    Navigator.pop(
                      ctx,
                      _InstallConfirmResult(unitNo: u, effectiveAt: effectiveAt),
                    );
                  },
                  child: const Text('Install'),
                ),
              ],
            );
          },
        );
      },
    );
    unitCtrl.dispose();
    if (confirmed == null || !mounted) return;

    var override = false;
    String? note;
    if (esa == 'yellow_only') {
      final pressCfg = _settings.presses[_pressId];
      final noEsa = pressCfg?.noEsaUnits ?? [];
      if (!noEsa.contains(confirmed.unitNo)) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Yellow-only recommendation'),
            content: const Text(
              'Poor conductivity — recommended for yellow (no ESA) units only. Override?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Override')),
            ],
          ),
        );
        if (go != true) return;
        override = true;
        note = 'installer override yellow_only';
      }
    }
    try {
      await ImpressionService.instance.installRoller(
        pressId: _pressId,
        unitNo: confirmed.unitNo,
        cycleId: cycleId,
        yellowOnlyOverride: override,
        yellowOnlyNote: note,
        effectiveAt: confirmed.effectiveAt,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Installed')));
      }
      _refreshCounts();
      _refreshCompliance();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showStrip(String cycleId, Map<String, dynamic> data) async {
    var disposition = 'send_out';
    var sendType = 'recover';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Strip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: disposition,
                items: const [
                  DropdownMenuItem(value: 'send_out', child: Text('Send out sleeve')),
                  DropdownMenuItem(value: 'scrap', child: Text('Scrap')),
                  DropdownMenuItem(value: 'retest', child: Text('Retest electrical')),
                ],
                onChanged: (v) => setLocal(() => disposition = v ?? disposition),
              ),
              if (disposition == 'send_out')
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: sendType,
                  items: (_settings.sendOutTypes.isEmpty
                          ? ['recover', 'regrind']
                          : _settings.sendOutTypes)
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => sendType = v ?? sendType),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Strip')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ImpressionService.instance.strip(
        cycleId: cycleId,
        sleeveDisposition: disposition,
        sendOutType: sendType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stripped')));
      }
      _refreshCounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showSendOut(String cycleId, Map<String, dynamic> data) async {
    final vendor = _settings.vendors.isNotEmpty
        ? _settings.vendors.first
        : 'Rubber Engineering';
    try {
      await ImpressionService.instance.sendOut(
        cycleId: cycleId,
        vendor: vendor,
        sendOutType: 'recover',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent out')));
      }
      _refreshCounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _PressMap extends StatelessWidget {
  final String pressId;
  final bool canAct;
  final void Function(int unitNo, Map<String, dynamic> data) onUnitTap;
  final void Function(String cycleId) onOpenCycle;

  const _PressMap({
    required this.pressId,
    required this.canAct,
    required this.onUnitTap,
    required this.onOpenCycle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ImpressionService.instance.watchSlots(pressId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!;
        if (docs.isEmpty) {
          return const Text('No unit slots — run seed script.');
        }
        return Column(
          children: docs.map((d) {
            final m = d.data();
            final unit = (m['unitNo'] as num?)?.toInt() ?? 0;
            final state = m['state'] ?? '';
            final shaft = m['shaftNo'] ?? '—';
            final sleeve = m['sleeveId'] ?? '—';
            final streak = m['overMaxStreak'] ?? 0;
            final awaiting = state == 'awaiting_install';
            final scheme = Theme.of(context).colorScheme;
            return ListTile(
              dense: true,
              onTap: () => onUnitTap(unit, m),
              leading: CircleAvatar(
                backgroundColor: awaiting ? scheme.tertiary : kBrandOrange,
                child: Text(
                  '$unit',
                  style: TextStyle(
                    color: awaiting ? scheme.onTertiary : Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
              title: Text('U$unit · $shaft / $sleeve'),
              subtitle: Text(
                awaiting
                    ? 'Awaiting install — tap to install'
                    : 'Installed · streak $streak${m['lastIrOverMax'] == true ? ' · last IR over max' : ''}',
              ),
              trailing: m['cycleId'] != null
                  ? IconButton(
                      icon: const Icon(Icons.history, size: 20),
                      onPressed: () => onOpenCycle(m['cycleId'] as String),
                    )
                  : null,
            );
          }).toList(),
        );
      },
    );
  }
}

class _SpareList extends StatelessWidget {
  final String pressId;
  final bool canInstall;
  final void Function(String cycleId, String? esa)? onInstall;
  final void Function(String cycleId) onOpen;

  const _SpareList({
    required this.pressId,
    required this.canInstall,
    this.onInstall,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ImpressionService.instance.watchCyclesByState('spare_ready', pressId: pressId),
      builder: (context, snap) {
        final docs = snap.data ?? [];
        if (docs.isEmpty) return const Text('No spares ready');
        return Column(
          children: docs.map((d) {
            final m = d.data();
            final esa = m['esaSuitability']?.toString();
            return ListTile(
              dense: true,
              onTap: () => onOpen(d.id),
              title: Text('${m['shaftNo']} / ${m['sleeveId']}'),
              subtitle: Text(
                '${m['cycleNo']} · ESA $esa'
                '${esa == 'yellow_only' ? ' ⚠ yellow only' : ''}',
              ),
              trailing: canInstall && onInstall != null
                  ? TextButton(
                      onPressed: () => onInstall!(d.id, esa),
                      child: const Text('Install'),
                    )
                  : null,
            );
          }).toList(),
        );
      },
    );
  }
}

class _CycleQueue extends StatelessWidget {
  final String state;
  final bool enabled;
  final String actionLabel;
  final Future<void> Function(String id, Map<String, dynamic> data)? onAction;
  final void Function(String id) onOpen;

  const _CycleQueue({
    required this.state,
    required this.enabled,
    required this.actionLabel,
    this.onAction,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ImpressionService.instance.watchCyclesByState(state),
      builder: (context, snap) {
        final docs = snap.data ?? [];
        if (docs.isEmpty) return Text('Empty ($state)');
        return Column(
          children: docs.map((d) {
            final m = d.data();
            return ListTile(
              dense: true,
              onTap: () => onOpen(d.id),
              title: Text('${m['cycleNo'] ?? d.id} · ${m['shaftNo']} / ${m['sleeveId']}'),
              subtitle: Text('${m['pressId'] ?? ''}'),
              trailing: enabled && onAction != null
                  ? TextButton(
                      onPressed: () => onAction!(d.id, m),
                      child: Text(actionLabel),
                    )
                  : Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 18),
            );
          }).toList(),
        );
      },
    );
  }
}

class _InstallConfirmResult {
  final int unitNo;
  final DateTime effectiveAt;

  const _InstallConfirmResult({
    required this.unitNo,
    required this.effectiveAt,
  });
}
