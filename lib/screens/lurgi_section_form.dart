import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../providers/current_employee_provider.dart';
import '../providers/lurgi_drafts.dart';
import '../providers/lurgi_provider.dart';
import '../utils/ink_pickers.dart';
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';

/// Which morning sections a form submits.
enum LurgiSection {
  utilities,
  water,
  air,
  geyser,
  tanks,
  all,
}

extension LurgiSectionX on LurgiSection {
  String get title => switch (this) {
        LurgiSection.utilities => 'Gas / Boiler / Softener',
        LurgiSection.water => 'Fresh & Effluent',
        LurgiSection.air => 'Air Condenser',
        LurgiSection.geyser => 'Geyser',
        LurgiSection.tanks => 'Toloul Tanks',
        LurgiSection.all => 'Morning Round',
      };

  bool get includeUtilities =>
      this == LurgiSection.utilities || this == LurgiSection.all;
  bool get includeWater =>
      this == LurgiSection.water || this == LurgiSection.all;
  bool get includeAir => this == LurgiSection.air || this == LurgiSection.all;
  bool get includeGeyser =>
      this == LurgiSection.geyser || this == LurgiSection.all;
  bool get includeTanks =>
      this == LurgiSection.tanks || this == LurgiSection.all;
}

/// Shared capture form for one or all Phase-1 morning sections.
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
  /// Date key last seeded into controllers (re-seed when admin changes day).
  String? _seededForKey;
  bool _submitting = false;
  /// Prefer restored draft over Firestore seed until user changes day / saves.
  bool _loadedDraft = false;
  bool _draftBannerShown = false;
  /// After successful save+pop, do not re-write draft from dispose.
  bool _suppressDraftPersist = false;
  /// Entry stamp; admins may override for period testing (ink pattern).
  DateTime _effectiveAt = DateTime.now();

  String get _dateKey => lurgiDateKey(_effectiveAt);

  String get _draftKey => widget.section.name;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(lurgiSectionFormDraftProvider(_draftKey));
    _gasMech = TextEditingController(text: draft?.gasMech ?? '');
    _gasElec = TextEditingController(text: draft?.gasElec ?? '');
    _boiler = TextEditingController(text: draft?.boiler ?? '');
    _softener = TextEditingController(text: draft?.softener ?? '');
    _fresh = TextEditingController(text: draft?.fresh ?? '');
    _effluent = TextEditingController(text: draft?.effluent ?? '');
    _air1 = TextEditingController(text: draft?.air1 ?? '');
    _air2 = TextEditingController(text: draft?.air2 ?? '');
    _geyserTemp = TextEditingController(text: draft?.geyserTemp ?? '');
    _geyserComments = TextEditingController(text: draft?.geyserComments ?? '');
    _tank1 = TextEditingController(text: draft?.tank1 ?? '');
    _tank2 = TextEditingController(text: draft?.tank2 ?? '');
    _tank3 = TextEditingController(text: draft?.tank3 ?? '');
    if (draft != null && !draft.isEmpty) {
      _loadedDraft = true;
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
        _effectiveAt =
            DateTime.fromMillisecondsSinceEpoch(draft.effectiveAtMs!);
      }
      _seededForKey = lurgiDateKey(_effectiveAt);
    }
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt == null || !mounted) return;
    setState(() {
      _effectiveAt = dt;
      _seededForKey = null;
      // Date change: allow Firestore seed for the new day.
      _loadedDraft = false;
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
      );

  void _persistDraft() {
    final draft = _captureDraft();
    ref.read(lurgiSectionFormDraftProvider(_draftKey).notifier).state =
        draft.isEmpty ? null : draft;
  }

  void _clearDraft() {
    ref.read(lurgiSectionFormDraftProvider(_draftKey).notifier).state = null;
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
    super.dispose();
  }

  void _clearFields() {
    for (final c in [
      _gasMech,
      _gasElec,
      _boiler,
      _softener,
      _fresh,
      _effluent,
      _air1,
      _air2,
      _geyserTemp,
      _geyserComments,
      _tank1,
      _tank2,
      _tank3,
    ]) {
      c.clear();
    }
    _tank1Dir = null;
    _tank2Dir = null;
    _tank3Dir = null;
    _gasMechReset = false;
    _gasElecReset = false;
    _boilerReset = false;
    _softenerReset = false;
    _freshReset = false;
    _effluentReset = false;
    _air1Reset = false;
    _air2Reset = false;
  }

  void _scheduleSeed(LurgiDailyRound? dayRound, {required bool loaded}) {
    // Keep in-progress draft; do not overwrite with server values.
    if (_loadedDraft) return;
    if (!loaded || _seededForKey == _dateKey) return;
    // Avoid setState / controller writes during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _seededForKey == _dateKey || _loadedDraft) return;
      _seededForKey = _dateKey;
      _clearFields();
      if (dayRound == null) {
        setState(() {});
        return;
      }
      void setIf(TextEditingController c, double? v) {
        if (v != null) c.text = _fmt(v);
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
      if (dayRound.geyserComments != null) {
        _geyserComments.text = dayRound.geyserComments!;
      }
      setIf(_tank1, dayRound.tank1Litres);
      setIf(_tank2, dayRound.tank2Litres);
      setIf(_tank3, dayRound.tank3Litres);
      setState(() {
        _tank1Dir = dayRound.tank1Direction;
        _tank2Dir = dayRound.tank2Direction;
        _tank3Dir = dayRound.tank3Direction;
      });
    });
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _reqNum(String? raw, String label) {
    final d = _parse(raw ?? '');
    if (d == null) return 'Enter $label';
    if (d < 0) return 'Must be ≥ 0';
    return null;
  }

  Future<void> _submit(LurgiDailyRound? previous) async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;

    final s = widget.section;
    final problems = <String>[];

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
    final adminStamp =
        role_utils.isAdmin(emp) || role_utils.isAdmin(currentEmployee);
    setState(() => _submitting = true);
    try {
      final round = LurgiDailyRound(
        dateKey: _dateKey,
        gasMechanical: gasMech,
        gasElectrical: gasElec,
        boilerFeed: boiler,
        softener: softener,
        freshWater: fresh,
        effluent: effluent,
        airMeter1: air1,
        airMeter2: air2,
        geyserTemp: geyserTemp,
        geyserComments: geyserComments,
        tank1Litres: t1,
        tank1Direction: t1d,
        tank2Litres: t2,
        tank2Direction: t2d,
        tank3Litres: t3,
        tank3Direction: t3d,
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
            // Only pin section timestamps when admin overrode the clock.
            effectiveAt: adminStamp ? _effectiveAt : null,
          );
      if (!mounted) return;
      _clearDraft();
      _loadedDraft = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.section.title} saved.')),
      );
      if (widget.section != LurgiSection.all) {
        _suppressDraftPersist = true;
        Navigator.pop(context);
      }
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
    final df = DateFormat('EEE d MMM HH:mm');
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
            if (_loadedDraft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Unsaved draft — leave and return any time; cleared after save.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            if (canEditDate)
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text('Entry date: ${df.format(_effectiveAt)}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: Alignment.centerLeft,
                ),
              )
            else
              Text(
                'Date: $_dateKey · logged in as ${currentEmployee?.name ?? "—"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (canEditDate) ...[
              const SizedBox(height: 4),
              Text(
                'Admin test override · date_key $_dateKey · ${currentEmployee?.name ?? "—"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (widget.section.includeUtilities)
              _sectionBlock(
                context,
                title: 'Gas / Boiler / Softener',
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
                title: 'Fresh & Effluent water',
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
                title: 'Air condenser',
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
                    ),
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
                  ),
                ],
              ),
            if (widget.section.includeTanks)
              _sectionBlock(
                context,
                title: 'Toloul tanks (litres)',
                children: [
                  _tankRow(
                    context,
                    label: 'Tank 1',
                    controller: _tank1,
                    direction: _tank1Dir,
                    onDir: (v) => setState(() => _tank1Dir = v),
                  ),
                  _tankRow(
                    context,
                    label: 'Tank 2',
                    controller: _tank2,
                    direction: _tank2Dir,
                    onDir: (v) => setState(() => _tank2Dir = v),
                  ),
                  _tankRow(
                    context,
                    label: 'Tank 3',
                    controller: _tank3,
                    direction: _tank3Dir,
                    onDir: (v) => setState(() => _tank3Dir = v),
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

  /// Clear visual block so multi-section Morning Round stays scannable.
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
            onChanged: (_) => setState(() {}),
            validator: (v) => _reqNum(v, label),
          ),
          if (previous != null &&
              current != null &&
              !reset &&
              current < previous)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Meter was reset'),
              value: reset,
              onChanged: (v) => onReset(v ?? false),
            )
          else if (previous != null)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Meter was reset'),
              value: reset,
              onChanged: (v) => onReset(v ?? false),
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
            validator: (v) => _reqNum(v, '$label level'),
          ),
          const SizedBox(height: 8),
          Text(
            'Flow',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          // Large segmented toggle — easier on the floor than a dropdown.
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'in',
                label: Text('In'),
                icon: Icon(Icons.arrow_downward, size: 18),
              ),
              ButtonSegment(
                value: 'out',
                label: Text('Out'),
                icon: Icon(Icons.arrow_upward, size: 18),
              ),
            ],
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            selected: direction == null ? <String>{} : {direction},
            onSelectionChanged: (set) {
              if (set.isEmpty) {
                onDir(null);
              } else {
                onDir(set.first);
              }
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.comfortable,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
