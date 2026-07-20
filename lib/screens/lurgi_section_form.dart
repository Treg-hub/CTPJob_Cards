import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../providers/current_employee_provider.dart';
import '../providers/lurgi_drafts.dart';
import '../providers/lurgi_provider.dart';
import '../utils/ink_pickers.dart';
import '../utils/lurgi_draft_store.dart';
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/lurgi_operator_note.dart';

/// Which morning section a form submits (one area at a time — walk the plant).
enum LurgiSection {
  utilities,
  water,
  air,
  geyser,
  tanks,
}

extension LurgiSectionX on LurgiSection {
  String get title => switch (this) {
        LurgiSection.utilities => 'Gas / Boiler / Softener',
        LurgiSection.water => 'Fresh & Effluent',
        LurgiSection.air => 'Air Condenser',
        LurgiSection.geyser => 'Geyser',
        LurgiSection.tanks => 'Toloul Tanks',
      };

  bool get includeUtilities => this == LurgiSection.utilities;
  bool get includeWater => this == LurgiSection.water;
  bool get includeAir => this == LurgiSection.air;
  bool get includeGeyser => this == LurgiSection.geyser;
  bool get includeTanks => this == LurgiSection.tanks;
}

/// Shared capture form for one Phase-1 morning section.
class LurgiSectionFormScreen extends ConsumerStatefulWidget {
  const LurgiSectionFormScreen({super.key, required this.section});

  final LurgiSection section;

  @override
  ConsumerState<LurgiSectionFormScreen> createState() =>
      _LurgiSectionFormScreenState();
}

class _LurgiSectionFormScreenState
    extends ConsumerState<LurgiSectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qty = NumberFormat('#,##0.##');

  late final TextEditingController _gasMech;
  late final TextEditingController _gasElec;
  late final TextEditingController _boiler;
  late final TextEditingController _softener;
  late final TextEditingController _fresh;
  late final TextEditingController _effluent;
  late final TextEditingController _air1;
  late final TextEditingController _air2;
  late final TextEditingController _geyserTemp;
  late final TextEditingController _geyserComments;
  late final TextEditingController _tank1;
  late final TextEditingController _tank2;
  late final TextEditingController _tank3;
  late final TextEditingController _spanComment;

  String? _tank1Dir;
  String? _tank2Dir;
  String? _tank3Dir;
  bool _gasMechReset = false;
  bool _gasElecReset = false;
  bool _boilerReset = false;
  bool _softenerReset = false;
  bool _freshReset = false;
  bool _effluentReset = false;
  bool _air1Reset = false;
  bool _air2Reset = false;
  String? _seededForKey;
  bool _submitting = false;
  bool _loadedDraft = false;
  bool _draftBannerShown = false;
  bool _suppressDraftPersist = false;
  bool _dirty = false;
  bool _dirsDefaulted = false;
  bool _resetsSeeded = false;
  /// Admin may override; operators always use now.
  DateTime _effectiveAt = DateTime.now();
  bool _spanAcknowledged = false;

  String get _dateKey => lurgiDateKey(_effectiveAt);
  String get _draftKey => widget.section.name;

  void _markDirty() {
    if (!_dirty) _dirty = true;
  }

  @override
  void initState() {
    super.initState();
    final mem = ref.read(lurgiSectionFormDraftProvider(_draftKey));
    _gasMech = TextEditingController(text: mem?.gasMech ?? '');
    _gasElec = TextEditingController(text: mem?.gasElec ?? '');
    _boiler = TextEditingController(text: mem?.boiler ?? '');
    _softener = TextEditingController(text: mem?.softener ?? '');
    _fresh = TextEditingController(text: mem?.fresh ?? '');
    _effluent = TextEditingController(text: mem?.effluent ?? '');
    _air1 = TextEditingController(text: mem?.air1 ?? '');
    _air2 = TextEditingController(text: mem?.air2 ?? '');
    _geyserTemp = TextEditingController(text: mem?.geyserTemp ?? '');
    _geyserComments = TextEditingController(text: mem?.geyserComments ?? '');
    _tank1 = TextEditingController(text: mem?.tank1 ?? '');
    _tank2 = TextEditingController(text: mem?.tank2 ?? '');
    _tank3 = TextEditingController(text: mem?.tank3 ?? '');
    _spanComment = TextEditingController(text: mem?.spanComment ?? '');
    if (mem != null && !mem.isEmpty) {
      _applyDraft(mem);
    } else {
      _hydrateDiskDraft();
    }
  }

  void _applyDraft(LurgiSectionFormDraft draft) {
    _loadedDraft = true;
    _dirty = true;
    _tank1Dir = draft.tank1Dir;
    _tank2Dir = draft.tank2Dir;
    _tank3Dir = draft.tank3Dir;
    _gasMechReset = draft.gasMechReset;
    _gasElecReset = draft.gasElecReset;
    _boilerReset = draft.boilerReset;
    _softenerReset = draft.softenerReset;
    _freshReset = draft.freshReset;
    _effluentReset = draft.effluentReset;
    _air1Reset = draft.air1Reset;
    _air2Reset = draft.air2Reset;
    if (draft.effectiveAtMs != null) {
      _effectiveAt = DateTime.fromMillisecondsSinceEpoch(draft.effectiveAtMs!);
    }
    _seededForKey = lurgiDateKey(_effectiveAt);
  }

  Future<void> _hydrateDiskDraft() async {
    final disk = await LurgiDraftStore.loadSection(_draftKey);
    if (!mounted || disk == null || disk.isEmpty) return;
    if (_dirty) return;
    _gasMech.text = disk.gasMech;
    _gasElec.text = disk.gasElec;
    _boiler.text = disk.boiler;
    _softener.text = disk.softener;
    _fresh.text = disk.fresh;
    _effluent.text = disk.effluent;
    _air1.text = disk.air1;
    _air2.text = disk.air2;
    _geyserTemp.text = disk.geyserTemp;
    _geyserComments.text = disk.geyserComments;
    _tank1.text = disk.tank1;
    _tank2.text = disk.tank2;
    _tank3.text = disk.tank3;
    _spanComment.text = disk.spanComment;
    _applyDraft(disk);
    ref.read(lurgiSectionFormDraftProvider(_draftKey).notifier).state = disk;
    setState(() {});
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt == null || !mounted) return;
    setState(() {
      _effectiveAt = dt;
      _seededForKey = null;
      _loadedDraft = false;
      _dirty = false;
      _dirsDefaulted = false;
      _resetsSeeded = false;
      _spanAcknowledged = false;
      _tank1Dir = null;
      _tank2Dir = null;
      _tank3Dir = null;
    });
  }

  LurgiSectionFormDraft _captureDraft() => LurgiSectionFormDraft(
        gasMech: _gasMech.text,
        gasElec: _gasElec.text,
        boiler: _boiler.text,
        softener: _softener.text,
        fresh: _fresh.text,
        effluent: _effluent.text,
        air1: _air1.text,
        air2: _air2.text,
        geyserTemp: _geyserTemp.text,
        geyserComments: _geyserComments.text,
        tank1: _tank1.text,
        tank2: _tank2.text,
        tank3: _tank3.text,
        tank1Dir: _tank1Dir,
        tank2Dir: _tank2Dir,
        tank3Dir: _tank3Dir,
        gasMechReset: _gasMechReset,
        gasElecReset: _gasElecReset,
        boilerReset: _boilerReset,
        softenerReset: _softenerReset,
        freshReset: _freshReset,
        effluentReset: _effluentReset,
        air1Reset: _air1Reset,
        air2Reset: _air2Reset,
        effectiveAtMs: _effectiveAt.millisecondsSinceEpoch,
        spanComment: _spanComment.text,
      );

  void _persistDraft() {
    final draft = _captureDraft();
    ref.read(lurgiSectionFormDraftProvider(_draftKey).notifier).state =
        draft.isEmpty ? null : draft;
    LurgiDraftStore.saveSection(_draftKey, draft.isEmpty ? null : draft);
  }

  void _clearDraft() {
    ref.read(lurgiSectionFormDraftProvider(_draftKey).notifier).state = null;
    LurgiDraftStore.saveSection(_draftKey, null);
  }

  @override
  void dispose() {
    if (!_suppressDraftPersist) _persistDraft();
    _gasMech.dispose();
    _gasElec.dispose();
    _boiler.dispose();
    _softener.dispose();
    _fresh.dispose();
    _effluent.dispose();
    _air1.dispose();
    _air2.dispose();
    _geyserTemp.dispose();
    _geyserComments.dispose();
    _tank1.dispose();
    _tank2.dispose();
    _tank3.dispose();
    _spanComment.dispose();
    super.dispose();
  }

  void _scheduleSeed(LurgiDailyRound? dayRound, {required bool loaded}) {
    if (_loadedDraft || _dirty) return;
    if (!loaded || _seededForKey == _dateKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _seededForKey == _dateKey || _loadedDraft || _dirty) {
        return;
      }
      _seededForKey = _dateKey;
      if (dayRound == null) {
        setState(() {});
        return;
      }
      void setIf(TextEditingController c, double? v) {
        if (v != null && c.text.trim().isEmpty) c.text = _fmt(v);
      }

      setIf(_gasMech, dayRound.gasMechanical);
      setIf(_gasElec, dayRound.gasElectrical);
      setIf(_boiler, dayRound.boilerFeed);
      setIf(_softener, dayRound.softener);
      setIf(_fresh, dayRound.freshWater);
      setIf(_effluent, dayRound.effluent);
      setIf(_air1, dayRound.airMeter1);
      setIf(_air2, dayRound.airMeter2);
      setIf(_geyserTemp, dayRound.geyserTemp);
      if (dayRound.geyserComments != null &&
          _geyserComments.text.trim().isEmpty) {
        _geyserComments.text = dayRound.geyserComments!;
      }
      setIf(_tank1, dayRound.tank1Litres);
      setIf(_tank2, dayRound.tank2Litres);
      setIf(_tank3, dayRound.tank3Litres);
      if (dayRound.meterSpanComment != null &&
          _spanComment.text.trim().isEmpty) {
        _spanComment.text = dayRound.meterSpanComment!;
      }
      setState(() {});
    });
  }

  void _scheduleSeedResets(LurgiDailyRound? dayRound, {required bool ready}) {
    if (!ready || _resetsSeeded || _dirty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _resetsSeeded || _dirty) return;
      _resetsSeeded = true;
      if (dayRound == null) return;
      setState(() {
        _gasMechReset = dayRound.gasMechanicalReset;
        _gasElecReset = dayRound.gasElectricalReset;
        _boilerReset = dayRound.boilerFeedReset;
        _softenerReset = dayRound.softenerReset;
        _freshReset = dayRound.freshWaterReset;
        _effluentReset = dayRound.effluentReset;
        _air1Reset = dayRound.airMeter1Reset;
        _air2Reset = dayRound.airMeter2Reset;
      });
    });
  }

  void _scheduleDefaultDirs(
    LurgiDailyRound? dayRound,
    LurgiDailyRound? previous, {
    required bool ready,
  }) {
    if (!ready || _dirsDefaulted) return;
    final d1 = dayRound?.tank1Direction ?? previous?.tank1Direction;
    final d2 = dayRound?.tank2Direction ?? previous?.tank2Direction;
    final d3 = dayRound?.tank3Direction ?? previous?.tank3Direction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dirsDefaulted) return;
      _dirsDefaulted = true;
      if (d1 == null && d2 == null && d3 == null) return;
      if (_tank1Dir != null && _tank2Dir != null && _tank3Dir != null) return;
      setState(() {
        _tank1Dir ??= d1;
        _tank2Dir ??= d2;
        _tank3Dir ??= d3;
      });
    });
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _reqNum(String? raw, String label) {
    final d = _parse(raw ?? '');
    if (d == null) return 'Enter $label';
    if (d < 0) return 'Must be ≥ 0';
    return null;
  }

  int? _spanDays(LurgiDailyRound? previous) {
    if (previous == null) return null;
    return lurgiDateKeyDaySpan(previous.dateKey, _dateKey);
  }

  Future<void> _submit(LurgiDailyRound? previous) async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;

    final s = widget.section;
    final problems = <String>[];
    final span = _spanDays(previous);
    final multiDay = span != null && span > 1;

    if (multiDay && !_spanAcknowledged) {
      problems.add('Acknowledge the multi-day gap warning below');
    }
    if (multiDay && _spanComment.text.trim().isEmpty) {
      problems.add('Add a short note for the multi-day gap');
    }

    double? gasMech, gasElec, boiler, softener;
    double? fresh, effluent, air1, air2, geyserTemp;
    double? t1, t2, t3;
    String? t1d, t2d, t3d;
    String? geyserComments;

    if (s.includeUtilities) {
      gasMech = _parse(_gasMech.text);
      gasElec = _parse(_gasElec.text);
      boiler = _parse(_boiler.text);
      softener = _parse(_softener.text);
      for (final e in [
        (gasMech, previous?.gasMechanical, _gasMechReset, 'Gas mechanical'),
        (gasElec, previous?.gasElectrical, _gasElecReset, 'Gas electrical'),
        (boiler, previous?.boilerFeed, _boilerReset, 'Boiler feed'),
        (softener, previous?.softener, _softenerReset, 'Softener'),
      ]) {
        final cur = e.$1;
        final prev = e.$2;
        final reset = e.$3;
        final name = e.$4;
        if (cur != null && prev != null && !reset && cur < prev) {
          problems.add('$name: below last — tick meter reset');
        }
      }
    }
    if (s.includeWater) {
      fresh = _parse(_fresh.text);
      effluent = _parse(_effluent.text);
      if (fresh != null &&
          previous?.freshWater != null &&
          !_freshReset &&
          fresh < previous!.freshWater!) {
        problems.add('Fresh water: below last — tick meter reset');
      }
      if (effluent != null &&
          previous?.effluent != null &&
          !_effluentReset &&
          effluent < previous!.effluent!) {
        problems.add('Effluent: below last — tick meter reset');
      }
      final intake = lurgiMeterDelta(
        previous?.freshWater,
        fresh ?? 0,
        reset: _freshReset,
      );
      final discharge = lurgiMeterDelta(
        previous?.effluent,
        effluent ?? 0,
        reset: _effluentReset,
      );
      if (intake != null &&
          discharge != null &&
          discharge > intake * 1.5 &&
          intake > 0) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discharge much higher than intake'),
            content: Text(
              'Intake ≈ ${_qty.format(intake)} · discharge ≈ ${_qty.format(discharge)}. '
              'Double-check meters before saving.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Review')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save anyway')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    if (s.includeAir) {
      air1 = _parse(_air1.text);
      air2 = _parse(_air2.text);
      if (air1 != null &&
          previous?.airMeter1 != null &&
          !_air1Reset &&
          air1 < previous!.airMeter1!) {
        problems.add('Air meter 1: below last — tick meter reset');
      }
      if (air2 != null &&
          previous?.airMeter2 != null &&
          !_air2Reset &&
          air2 < previous!.airMeter2!) {
        problems.add('Air meter 2: below last — tick meter reset');
      }
    }
    if (s.includeGeyser) {
      geyserTemp = _parse(_geyserTemp.text);
      final gNotes = _geyserComments.text.trim();
      geyserComments = gNotes.isEmpty ? null : gNotes;
      if (geyserTemp != null && (geyserTemp < 0 || geyserTemp > 100)) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unusual geyser temperature'),
            content: Text(
              '${_qty.format(geyserTemp)} °C is outside the usual 0–100 °C range. '
              'Confirm the dial reading.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Review')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save anyway')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    if (s.includeTanks) {
      t1 = _parse(_tank1.text);
      t2 = _parse(_tank2.text);
      t3 = _parse(_tank3.text);
      t1d = _tank1Dir;
      t2d = _tank2Dir;
      t3d = _tank3Dir;
      if (t1d == null || t2d == null || t3d == null) {
        problems.add('Set In/Out for each tank');
      }
    }

    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problems.join('\n'))),
      );
      return;
    }

    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final isAdmin =
        role_utils.isAdmin(emp) || role_utils.isAdmin(currentEmployee);
    setState(() => _submitting = true);
    try {
      final round = LurgiDailyRound(
        dateKey: _dateKey,
        gasMechanical: gasMech,
        gasElectrical: gasElec,
        boilerFeed: boiler,
        softener: softener,
        gasMechanicalReset: _gasMechReset,
        gasElectricalReset: _gasElecReset,
        boilerFeedReset: _boilerReset,
        softenerReset: _softenerReset,
        freshWater: fresh,
        effluent: effluent,
        freshWaterReset: _freshReset,
        effluentReset: _effluentReset,
        airMeter1: air1,
        airMeter2: air2,
        airMeter1Reset: _air1Reset,
        airMeter2Reset: _air2Reset,
        geyserTemp: geyserTemp,
        geyserComments: geyserComments,
        tank1Litres: t1,
        tank1Direction: t1d,
        tank2Litres: t2,
        tank2Direction: t2d,
        tank3Litres: t3,
        tank3Direction: t3d,
        meterBaselineDateKey: previous?.dateKey,
        meterSpanDays: span,
        meterSpanComment:
            multiDay ? _spanComment.text.trim() : null,
      );
      await ref.read(lurgiServiceProvider).saveRoundSections(
            round: round,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
            utilities: s.includeUtilities,
            water: s.includeWater,
            air: s.includeAir,
            geyser: s.includeGeyser,
            tanks: s.includeTanks,
            effectiveAt: isAdmin ? _effectiveAt : null,
          );
      if (!mounted) return;
      _clearDraft();
      _loadedDraft = false;
      _suppressDraftPersist = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.section.title} saved for $_dateKey.'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return OffSiteBlockedScreen(title: widget.section.title);
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.section.title)),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final canEditDate = role_utils.isAdmin(emp);
    final dayAsync = ref.watch(lurgiRoundForDateProvider(_dateKey));
    final prevAsync = ref.watch(lurgiPreviousRoundProvider(_dateKey));
    final dayRound = dayAsync.valueOrNull;
    final previous = prevAsync.valueOrNull;
    _scheduleSeed(dayRound, loaded: !dayAsync.isLoading);
    _scheduleSeedResets(dayRound, ready: !dayAsync.isLoading);
    _scheduleDefaultDirs(
      dayRound,
      previous,
      ready: !dayAsync.isLoading && !prevAsync.isLoading,
    );
    final df = DateFormat('EEE d MMM HH:mm');
    final span = _spanDays(previous);
    final multiDay = span != null && span > 1;
    if (_loadedDraft && !_draftBannerShown) {
      _draftBannerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft restored — unsaved entries kept'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.section.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ScreenInsets.symmetricScroll(context),
          children: [
            const LurgiOperatorNote(
              noteId: 'section_one_area',
              message:
                  'Save this area only, then open the next tile on the hub. '
                  'Walk: Gas → Water → Air → Geyser → Tanks. '
                  'Tick “Meter was reset” when a dial has rolled over.',
            ),
            if (_loadedDraft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Unsaved draft (survives app close today) — cleared after save.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            if (canEditDate)
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text('Entry date (admin): ${df.format(_effectiveAt)}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: Alignment.centerLeft,
                ),
              )
            else
              Text(
                'Date: $_dateKey · saved at current time · ${currentEmployee?.name ?? "—"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (canEditDate) ...[
              const SizedBox(height: 4),
              Text(
                'Admin date override · date_key $_dateKey',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (multiDay) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last capture was ${previous!.dateKey} ($span days ago)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Today’s meter usage includes that whole gap — not a single day. '
                        'You cannot backfill missed days; note the reason below.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('I understand this is a multi-day gap'),
                        value: _spanAcknowledged,
                        onChanged: (v) =>
                            setState(() => _spanAcknowledged = v ?? false),
                      ),
                      TextFormField(
                        controller: _spanComment,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Gap note (required)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (widget.section.includeUtilities)
              _sectionBlock(
                context,
                title: 'Gas / Boiler / Softener (dial units)',
                children: [
                  _meterField(
                    context,
                    controller: _gasMech,
                    label: 'Gas — mechanical',
                    previous: previous?.gasMechanical,
                    reset: _gasMechReset,
                    onReset: (v) => setState(() => _gasMechReset = v),
                  ),
                  _meterField(
                    context,
                    controller: _gasElec,
                    label: 'Gas — electrical',
                    previous: previous?.gasElectrical,
                    reset: _gasElecReset,
                    onReset: (v) => setState(() => _gasElecReset = v),
                  ),
                  _meterField(
                    context,
                    controller: _boiler,
                    label: 'Boiler feed (water)',
                    previous: previous?.boilerFeed,
                    reset: _boilerReset,
                    onReset: (v) => setState(() => _boilerReset = v),
                  ),
                  _meterField(
                    context,
                    controller: _softener,
                    label: 'Softener (water)',
                    previous: previous?.softener,
                    reset: _softenerReset,
                    onReset: (v) => setState(() => _softenerReset = v),
                  ),
                ],
              ),
            if (widget.section.includeWater)
              _sectionBlock(
                context,
                title: 'Fresh & Effluent water (dial units)',
                children: [
                  _meterField(
                    context,
                    controller: _fresh,
                    label: 'Fresh water meter',
                    previous: previous?.freshWater,
                    reset: _freshReset,
                    onReset: (v) => setState(() => _freshReset = v),
                    deltaLabel: 'Intake today',
                  ),
                  _meterField(
                    context,
                    controller: _effluent,
                    label: 'Effluent meter',
                    previous: previous?.effluent,
                    reset: _effluentReset,
                    onReset: (v) => setState(() => _effluentReset = v),
                    deltaLabel: 'Discharge today',
                  ),
                  _waterNetHint(previous),
                ],
              ),
            if (widget.section.includeAir)
              _sectionBlock(
                context,
                title: 'Air condenser (dial units)',
                children: [
                  _meterField(
                    context,
                    controller: _air1,
                    label: 'Meter 1',
                    previous: previous?.airMeter1,
                    reset: _air1Reset,
                    onReset: (v) => setState(() => _air1Reset = v),
                  ),
                  _meterField(
                    context,
                    controller: _air2,
                    label: 'Meter 2',
                    previous: previous?.airMeter2,
                    reset: _air2Reset,
                    onReset: (v) => setState(() => _air2Reset = v),
                  ),
                ],
              ),
            if (widget.section.includeGeyser)
              _sectionBlock(
                context,
                title: 'Geyser',
                children: [
                  TextFormField(
                    controller: _geyserTemp,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Geyser temperature',
                      suffixText: '°C',
                      border: OutlineInputBorder(),
                      helperText: 'Usual range 0–100 °C',
                    ),
                    onChanged: (_) => _markDirty(),
                    validator: (v) => _reqNum(v, 'temperature'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _geyserComments,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Comments (optional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _markDirty(),
                  ),
                ],
              ),
            if (widget.section.includeTanks)
              _sectionBlock(
                context,
                title: 'Toloul tanks (litres)',
                children: [
                  if (previous != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Last levels (${previous.dateKey}): '
                        'T1 ${_qty.format(previous.tank1Litres ?? 0)} · '
                        'T2 ${_qty.format(previous.tank2Litres ?? 0)} · '
                        'T3 ${_qty.format(previous.tank3Litres ?? 0)} L',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  _tankRow(
                    context,
                    label: 'Tank 1',
                    controller: _tank1,
                    direction: _tank1Dir,
                    onDir: (v) => setState(() {
                      _markDirty();
                      _tank1Dir = v;
                    }),
                  ),
                  _tankRow(
                    context,
                    label: 'Tank 2',
                    controller: _tank2,
                    direction: _tank2Dir,
                    onDir: (v) => setState(() {
                      _markDirty();
                      _tank2Dir = v;
                    }),
                  ),
                  _tankRow(
                    context,
                    label: 'Tank 3',
                    controller: _tank3,
                    direction: _tank3Dir,
                    onDir: (v) => setState(() {
                      _markDirty();
                      _tank3Dir = v;
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'In = recovering into tank · Out = pumping to overhead for pressroom',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _submitting ? null : () => _submit(previous),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_submitting ? 'Saving…' : 'Save'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _waterNetHint(LurgiDailyRound? previous) {
    final fresh = _parse(_fresh.text);
    final eff = _parse(_effluent.text);
    if (fresh == null || eff == null) return const SizedBox.shrink();
    final intake = lurgiMeterDelta(
      previous?.freshWater,
      fresh,
      reset: _freshReset,
    );
    final discharge = lurgiMeterDelta(
      previous?.effluent,
      eff,
      reset: _effluentReset,
    );
    if (intake == null || discharge == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Net balance available after first prior-day baseline.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final net = intake - discharge;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Today intake ${_qty.format(intake)} · discharge ${_qty.format(discharge)} · net ${_qty.format(net)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _sectionBlock(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _meterField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required double? previous,
    required bool reset,
    required ValueChanged<bool> onReset,
    String deltaLabel = 'Today',
  }) {
    final current = _parse(controller.text);
    final delta = current == null
        ? null
        : lurgiMeterDelta(previous, current, reset: reset);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              helperText: previous != null
                  ? 'Last: ${_qty.format(previous)}'
                      '${delta != null ? ' · $deltaLabel: ${_qty.format(delta)}' : ''}'
                  : 'No previous reading yet',
            ),
            onChanged: (_) {
              _markDirty();
              setState(() {});
            },
            validator: (v) => _reqNum(v, label),
          ),
          if (previous != null &&
              current != null &&
              (reset || current < previous))
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Meter was reset'),
              value: reset,
              onChanged: (v) {
                _markDirty();
                onReset(v ?? false);
              },
            ),
        ],
      ),
    );
  }

  Widget _tankRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String? direction,
    required ValueChanged<String?> onDir,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final missing = direction == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '$label level',
              suffixText: 'L',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _markDirty(),
            validator: (v) => _reqNum(v, '$label level'),
          ),
          const SizedBox(height: 8),
          Text(
            'Flow (required)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: missing ? scheme.error : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _flowChoiceButton(
                  context,
                  label: 'In',
                  subtitle: 'Into tank',
                  icon: Icons.arrow_downward,
                  selected: direction == 'in',
                  onTap: () => onDir('in'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _flowChoiceButton(
                  context,
                  label: 'Out',
                  subtitle: 'To pressroom',
                  icon: Icons.arrow_upward,
                  selected: direction == 'out',
                  onTap: () => onDir('out'),
                ),
              ),
            ],
          ),
          if (missing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Tap In or Out for $label',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _flowChoiceButton(
    BuildContext context, {
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        selected ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final fg = selected ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: bg,
      elevation: selected ? 1 : 0,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.7),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: fg,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
