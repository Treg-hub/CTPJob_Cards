import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../providers/current_employee_provider.dart';
import '../providers/lurgi_provider.dart';
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
  bool _seeded = false;
  bool _submitting = false;

  String get _dateKey => lurgiDateKey();

  @override
  void initState() {
    super.initState();
    _gasMech = TextEditingController();
    _gasElec = TextEditingController();
    _boiler = TextEditingController();
    _softener = TextEditingController();
    _fresh = TextEditingController();
    _effluent = TextEditingController();
    _air1 = TextEditingController();
    _air2 = TextEditingController();
    _geyserTemp = TextEditingController();
    _geyserComments = TextEditingController();
    _tank1 = TextEditingController();
    _tank2 = TextEditingController();
    _tank3 = TextEditingController();
  }

  @override
  void dispose() {
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

  void _scheduleSeed(LurgiDailyRound? today) {
    if (_seeded || today == null) return;
    // Avoid setState / controller writes during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _seeded) return;
      _seeded = true;
      void setIf(TextEditingController c, double? v) {
        if (v != null) c.text = _fmt(v);
      }

      setIf(_gasMech, today.gasMechanical);
      setIf(_gasElec, today.gasElectrical);
      setIf(_boiler, today.boilerFeed);
      setIf(_softener, today.softener);
      setIf(_fresh, today.freshWater);
      setIf(_effluent, today.effluent);
      setIf(_air1, today.airMeter1);
      setIf(_air2, today.airMeter2);
      setIf(_geyserTemp, today.geyserTemp);
      if (today.geyserComments != null) {
        _geyserComments.text = today.geyserComments!;
      }
      setIf(_tank1, today.tank1Litres);
      setIf(_tank2, today.tank2Litres);
      setIf(_tank3, today.tank3Litres);
      setState(() {
        _tank1Dir = today.tank1Direction;
        _tank2Dir = today.tank2Direction;
        _tank3Dir = today.tank3Direction;
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
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.section.title} saved.')),
      );
      if (widget.section != LurgiSection.all) {
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

    final todayAsync = ref.watch(lurgiTodayRoundProvider);
    final prevAsync = ref.watch(lurgiPreviousRoundProvider(_dateKey));
    final today = todayAsync.valueOrNull;
    final previous = prevAsync.valueOrNull;
    _scheduleSeed(today);

    return Scaffold(
      appBar: AppBar(title: Text(widget.section.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ScreenInsets.symmetricScroll(context),
          children: [
            Text(
              'Date: $_dateKey · logged in as ${currentEmployee?.name ?? "—"}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (widget.section.includeUtilities) ...[
              _sectionHeader(context, 'Gas / Boiler / Softener'),
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
              const SizedBox(height: 16),
            ],
            if (widget.section.includeWater) ...[
              _sectionHeader(context, 'Fresh & Effluent water'),
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
              const SizedBox(height: 16),
            ],
            if (widget.section.includeAir) ...[
              _sectionHeader(context, 'Air condenser'),
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
              const SizedBox(height: 16),
            ],
            if (widget.section.includeGeyser) ...[
              _sectionHeader(context, 'Geyser'),
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
              const SizedBox(height: 16),
            ],
            if (widget.section.includeTanks) ...[
              _sectionHeader(context, 'Toloul tanks (litres)'),
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
              const SizedBox(height: 8),
              Text(
                'In = recovering into tank · Out = pumping to overhead for pressroom',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
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

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
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
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Flow',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  // ignore: deprecated_member_use
                  value: direction,
                  isExpanded: true,
                  hint: const Text('In/Out'),
                  items: const [
                    DropdownMenuItem(value: 'in', child: Text('In')),
                    DropdownMenuItem(value: 'out', child: Text('Out')),
                  ],
                  onChanged: onDir,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
