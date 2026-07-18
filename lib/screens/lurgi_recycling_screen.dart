import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../models/lurgi_recycling_run.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../providers/lurgi_drafts.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/ink_pickers.dart';
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/lurgi_period_banner.dart';

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
  final _day = DateFormat('EEE d MMM');

  late DateTime _startAt;
  late DateTime _finishAt;
  late final TextEditingController _steamTemp;
  late final TextEditingController _steamPress;
  late final TextEditingController _litres;
  late final TextEditingController _dirtyLevel;
  bool _cleaned = false;
  bool _submitting = false;
  bool _loadedDraft = false;
  bool _draftBannerShown = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(lurgiRecyclingDraftProvider);
    final now = DateTime.now();
    if (draft != null && !draft.isEmpty) {
      _loadedDraft = true;
      _steamTemp = TextEditingController(text: draft.steamTemp);
      _steamPress = TextEditingController(text: draft.steamPress);
      _litres = TextEditingController(text: draft.litres);
      _dirtyLevel = TextEditingController(text: draft.dirtyLevel);
      _cleaned = draft.cleaned;
      _startAt = draft.startAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(draft.startAtMs!)
          : now.subtract(const Duration(hours: 2));
      _finishAt = draft.finishAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(draft.finishAtMs!)
          : now;
    } else {
      _steamTemp = TextEditingController();
      _steamPress = TextEditingController();
      _litres = TextEditingController();
      _dirtyLevel = TextEditingController();
      _finishAt = now;
      _startAt = now.subtract(const Duration(hours: 2));
    }
  }

  void _persistDraft() {
    final draft = LurgiRecyclingDraft(
      steamTemp: _steamTemp.text,
      steamPress: _steamPress.text,
      litres: _litres.text,
      dirtyLevel: _dirtyLevel.text,
      cleaned: _cleaned,
      startAtMs: _startAt.millisecondsSinceEpoch,
      finishAtMs: _finishAt.millisecondsSinceEpoch,
    );
    ref.read(lurgiRecyclingDraftProvider.notifier).state =
        draft.isEmpty ? null : draft;
  }

  void _clearDraft() {
    ref.read(lurgiRecyclingDraftProvider.notifier).state = null;
    _loadedDraft = false;
  }

  @override
  void dispose() {
    _persistDraft();
    _steamTemp.dispose();
    _steamPress.dispose();
    _litres.dispose();
    _dirtyLevel.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = start ? _startAt : _finishAt;
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    final adminStamp =
        role_utils.isAdmin(emp) || role_utils.isAdmin(currentEmployee);

    if (adminStamp) {
      // Full date+time so admins can backdate runs into an open count period.
      final dt = await pickInkDateTime(context, initial);
      if (dt == null || !mounted) return;
      setState(() {
        if (start) {
          _startAt = dt;
        } else {
          _finishAt = dt;
        }
      });
      return;
    }

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
              // Bucket by start day (admin may backdate start/finish).
              dateKey: lurgiDateKey(_startAt),
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
      _clearDraft();
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

    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final canEditDate = role_utils.isAdmin(emp);
    final dayKey = lurgiDateKey(_startAt);
    final runsAsync = ref.watch(lurgiRecyclingRunsForDayProvider(dayKey));
    final periodAsync = ref.watch(lurgiPeriodRecyclingRunsProvider);
    final dayRuns = runsAsync.valueOrNull ?? [];
    final summary = LurgiRecyclingDaySummary.fromRuns(dayRuns);
    final periodSummary = ref.watch(lurgiPeriodRecyclingSummaryProvider);
    final settingsAsync = ref.watch(inkSettingsProvider);
    final periodFrom = settingsAsync.valueOrNull?.latestActiveCountDate;
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    final dayLabel =
        canEditDate && dayKey != lurgiDateKey() ? 'Selected day' : 'Today';
    if (_loadedDraft && !_draftBannerShown) {
      _draftBannerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft restored — unsaved run kept'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recycling Machine')),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          LurgiPeriodBanner(
            periodFrom: periodFrom,
            settingsLoading: settingsAsync.isLoading,
          ),
          const SizedBox(height: 10),
          if (_loadedDraft)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Unsaved draft — leave and return any time; cleared after save.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ),
          Text(
            canEditDate
                ? 'Admin: start/finish pick full date+time · date_key from start ($dayKey).'
                : 'Date: $dayKey · log each cycle when dirty toloul is processed.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$dayLabel · ${summary.runCount} run${summary.runCount == 1 ? '' : 's'} · '
                    '${_qty.format(summary.totalLitresRecycled)} L',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: appColors.lurgiDark,
                    ),
                  ),
                  if (periodFrom != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Open period · ${periodSummary.runCount} run${periodSummary.runCount == 1 ? '' : 's'} · '
                      '${_qty.format(periodSummary.totalLitresRecycled)} L',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ],
                ],
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
                        child: Text(
                          canEditDate
                              ? 'Start ${_df.format(_startAt)}'
                              : 'Start ${_time.format(_startAt)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(start: false),
                        child: Text(
                          canEditDate
                              ? 'Finish ${_df.format(_finishAt)}'
                              : 'Finish ${_time.format(_finishAt)}',
                        ),
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
            canEditDate && dayKey != lurgiDateKey()
                ? 'RUNS · $dayKey'
                : "TODAY'S RUNS",
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
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    canEditDate && dayKey != lurgiDateKey()
                        ? 'No recycling runs for $dayKey.'
                        : 'No recycling runs logged today.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final r in runs)
                    _runCard(r, scheme, appColors,
                        showFullDate: canEditDate && dayKey != lurgiDateKey()),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'EARLIER THIS COUNT PERIOD',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          periodAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load period: $e'),
            data: (runs) {
              final earlier =
                  runs.where((r) => r.dateKey != dayKey).toList();
              if (periodFrom == null && !settingsAsync.isLoading) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No active count period — history hidden.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }
              if (earlier.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No earlier recycling runs in this open period.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }
              return Column(
                children: [
                  for (final r in earlier)
                    _runCard(r, scheme, appColors, showFullDate: true),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _runCard(
    LurgiRecyclingRun r,
    ColorScheme scheme,
    AppColors appColors, {
    required bool showFullDate,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.recycling_outlined,
          color: appColors.lurgiAccent,
        ),
        title: Text(
          '${_qty.format(r.litresRecycled)} L · '
          '${_time.format(r.startAt)}–${_time.format(r.finishAt)}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          [
            if (showFullDate) _day.format(r.startAt),
            'Steam ${_qty.format(r.steamTemp)} / ${_qty.format(r.steamPress)}',
            'Dirty ${_qty.format(r.dirtyToloulLevelLitres)} L'
                '${r.machineCleaned ? ' · cleaned' : ''}',
            if (r.actorName.isNotEmpty) r.actorName,
            if (!showFullDate) _df.format(r.startAt),
          ].join(' · '),
        ),
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
