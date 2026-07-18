import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../models/lurgi_recycling_run.dart';
import '../providers/current_employee_provider.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';

/// Multi-run toloul recycling machine log.
class LurgiRecyclingScreen extends ConsumerStatefulWidget {
  const LurgiRecyclingScreen({super.key});

  @override
  ConsumerState<LurgiRecyclingScreen> createState() =>
      _LurgiRecyclingScreenState();
}

class _LurgiRecyclingScreenState extends ConsumerState<LurgiRecyclingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qty = NumberFormat('#,##0.##');
  final _time = DateFormat('HH:mm');
  final _df = DateFormat('EEE d MMM HH:mm');

  late DateTime _startAt;
  late DateTime _finishAt;
  final _steamTemp = TextEditingController();
  final _steamPress = TextEditingController();
  final _litres = TextEditingController();
  final _dirtyLevel = TextEditingController();
  bool _cleaned = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _finishAt = now;
    _startAt = now.subtract(const Duration(hours: 2));
  }

  @override
  void dispose() {
    _steamTemp.dispose();
    _steamPress.dispose();
    _litres.dispose();
    _dirtyLevel.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = start ? _startAt : _finishAt;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return;
    setState(() {
      final base = DateTime.now();
      final dt = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      if (start) {
        _startAt = dt;
      } else {
        _finishAt = dt;
      }
    });
  }

  double? _parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_finishAt.isBefore(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish time must be after start.')),
      );
      return;
    }

    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    setState(() => _submitting = true);
    try {
      await ref.read(lurgiServiceProvider).addRecyclingRun(
            LurgiRecyclingRun(
              dateKey: lurgiDateKey(),
              startAt: _startAt,
              finishAt: _finishAt,
              steamTemp: _parse(_steamTemp.text)!,
              steamPress: _parse(_steamPress.text)!,
              litresRecycled: _parse(_litres.text)!,
              dirtyToloulLevelLitres: _parse(_dirtyLevel.text)!,
              machineCleaned: _cleaned,
              actorClockNo: emp?.clockNo ?? '',
              actorName: emp?.name ?? '',
            ),
          );
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _steamTemp.clear();
        _steamPress.clear();
        _litres.clear();
        _dirtyLevel.clear();
        _cleaned = false;
        _finishAt = now;
        _startAt = now.subtract(const Duration(hours: 2));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recycling run logged.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
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
      return const OffSiteBlockedScreen(title: 'Recycling Machine');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recycling Machine')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final runsAsync = ref.watch(lurgiTodayRecyclingRunsProvider);
    final summary = ref.watch(lurgiTodayRecyclingSummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Recycling Machine')),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          Text(
            'Date: ${lurgiDateKey()} · log each cycle when dirty toloul is processed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: appColors.lurgiSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: appColors.lurgiDark.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Today · ${summary.runCount} run${summary.runCount == 1 ? '' : 's'} · '
                '${_qty.format(summary.totalLitresRecycled)} L recycled',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: appColors.lurgiDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'LOG RUN',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(start: true),
                        child: Text('Start ${_time.format(_startAt)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(start: false),
                        child: Text('Finish ${_time.format(_finishAt)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _numField(_steamTemp, 'Steam temperature'),
                _numField(_steamPress, 'Steam pressure'),
                _numField(_litres, 'Total litres recycled', suffix: 'L',
                    mustPositive: true),
                _numField(_dirtyLevel, 'Dirty toloul level', suffix: 'L'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Machine cleaned after run'),
                  value: _cleaned,
                  onChanged: (v) => setState(() => _cleaned = v ?? false),
                ),
                Text(
                  'Operator: ${currentEmployee?.name ?? "—"}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_submitting ? 'Saving…' : 'Log run'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "TODAY'S RUNS",
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          runsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load: $e'),
            data: (runs) {
              if (runs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No recycling runs logged today.'),
                );
              }
              return Column(
                children: [
                  for (final r in runs)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.recycling_outlined,
                          color: appColors.lurgiAccent,
                        ),
                        title: Text(
                          '${_qty.format(r.litresRecycled)} L · '
                          '${_time.format(r.startAt)}–${_time.format(r.finishAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            'Steam ${_qty.format(r.steamTemp)} / ${_qty.format(r.steamPress)}',
                            'Dirty ${_qty.format(r.dirtyToloulLevelLitres)} L'
                                '${r.machineCleaned ? ' · cleaned' : ''}',
                            if (r.actorName.isNotEmpty) r.actorName,
                            _df.format(r.startAt),
                          ].join(' · '),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _numField(
    TextEditingController c,
    String label, {
    String? suffix,
    bool mustPositive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
        validator: (v) {
          final d = double.tryParse((v ?? '').trim());
          if (d == null) return 'Required';
          if (d < 0) return 'Must be ≥ 0';
          if (mustPositive && d <= 0) return 'Must be > 0';
          return null;
        },
      ),
    );
  }
}
