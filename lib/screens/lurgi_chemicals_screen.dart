import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_chemical_usage.dart';
import '../models/lurgi_daily_round.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../providers/lurgi_drafts.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/ink_pickers.dart';
import '../utils/lurgi_draft_store.dart';
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/lurgi_operator_note.dart';
import '../widgets/lurgi_period_banner.dart';

/// Multi-entry effluent chemical usage. Day total = sum of all entries.
class LurgiChemicalsScreen extends ConsumerStatefulWidget {
  const LurgiChemicalsScreen({super.key});

  @override
  ConsumerState<LurgiChemicalsScreen> createState() =>
      _LurgiChemicalsScreenState();
}

class _LurgiChemicalsScreenState extends ConsumerState<LurgiChemicalsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qty = NumberFormat('#,##0.##');
  final _time = DateFormat('HH:mm');
  final _day = DateFormat('EEE d MMM');
  late final TextEditingController _caustic;
  late final TextEditingController _hcl;
  late final TextEditingController _salt;
  late final TextEditingController _naccolaint;
  late final TextEditingController _comments;
  bool _submitting = false;
  bool _loadedDraft = false;
  bool _draftBannerShown = false;
  /// Admin test override for date_key + recorded_at.
  DateTime _effectiveAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    final draft = ref.read(lurgiChemicalsDraftProvider);
    _caustic = TextEditingController(text: draft?.caustic ?? '');
    _hcl = TextEditingController(text: draft?.hcl ?? '');
    _salt = TextEditingController(text: draft?.salt ?? '');
    _naccolaint = TextEditingController(text: draft?.naccolaint ?? '');
    _comments = TextEditingController(text: draft?.comments ?? '');
    if (draft != null && !draft.isEmpty) {
      _loadedDraft = true;
      if (draft.effectiveAtMs != null) {
        _effectiveAt =
            DateTime.fromMillisecondsSinceEpoch(draft.effectiveAtMs!);
      }
    } else {
      _hydrateDisk();
    }
  }

  Future<void> _hydrateDisk() async {
    final d = await LurgiDraftStore.loadChemicals();
    if (!mounted || d == null || d.isEmpty) return;
    _caustic.text = d.caustic;
    _hcl.text = d.hcl;
    _salt.text = d.salt;
    _naccolaint.text = d.naccolaint;
    _comments.text = d.comments;
    if (d.effectiveAtMs != null) {
      _effectiveAt = DateTime.fromMillisecondsSinceEpoch(d.effectiveAtMs!);
    }
    _loadedDraft = true;
    ref.read(lurgiChemicalsDraftProvider.notifier).state = d;
    setState(() {});
  }

  void _persistDraft() {
    final draft = LurgiChemicalsDraft(
      caustic: _caustic.text,
      hcl: _hcl.text,
      salt: _salt.text,
      naccolaint: _naccolaint.text,
      comments: _comments.text,
      effectiveAtMs: _effectiveAt.millisecondsSinceEpoch,
    );
    ref.read(lurgiChemicalsDraftProvider.notifier).state =
        draft.isEmpty ? null : draft;
    LurgiDraftStore.saveChemicals(draft.isEmpty ? null : draft);
  }

  void _clearDraft() {
    ref.read(lurgiChemicalsDraftProvider.notifier).state = null;
    LurgiDraftStore.saveChemicals(null);
    _loadedDraft = false;
  }

  @override
  void dispose() {
    _persistDraft();
    _caustic.dispose();
    _hcl.dispose();
    _salt.dispose();
    _naccolaint.dispose();
    _comments.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt == null || !mounted) return;
    setState(() => _effectiveAt = dt);
  }

  double _parseOrZero(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? double.nan;
  }

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;

    final c = _parseOrZero(_caustic.text);
    final h = _parseOrZero(_hcl.text);
    final s = _parseOrZero(_salt.text);
    final n = _parseOrZero(_naccolaint.text);
    if ([c, h, s, n].any((v) => v.isNaN)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid numbers (or leave blank).')),
      );
      return;
    }
    if (c + h + s + n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one chemical > 0 kg.')),
      );
      return;
    }

    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final adminStamp =
        role_utils.isAdmin(emp) || role_utils.isAdmin(currentEmployee);
    final stamp = adminStamp ? _effectiveAt : DateTime.now();
    setState(() => _submitting = true);
    try {
      await ref.read(lurgiServiceProvider).addChemicalUsage(
            LurgiChemicalUsage(
              dateKey: lurgiDateKey(stamp),
              recordedAt: stamp,
              causticSodaKg: c,
              hydrochloricAcidKg: h,
              sodiumChlorideKg: s,
              naccolaintKg: n,
              comments: _comments.text.trim().isEmpty
                  ? null
                  : _comments.text.trim(),
              actorClockNo: emp?.clockNo ?? '',
              actorName: emp?.name ?? '',
            ),
          );
      if (!mounted) return;
      _caustic.clear();
      _hcl.clear();
      _salt.clear();
      _naccolaint.clear();
      _comments.clear();
      _clearDraft();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chemical usage added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _requestVoid(LurgiChemicalUsage e) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request void'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Totals still include this entry until a manager voids it on Pulse.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(lurgiServiceProvider).requestChemicalVoid(
            docId: e.id!,
            reason: reasonCtrl.text,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Void requested — wait for desk.')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$err')));
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _setNoneToday(bool value) async {
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final adminStamp =
        role_utils.isAdmin(emp) || role_utils.isAdmin(currentEmployee);
    final dayKey =
        adminStamp ? lurgiDateKey(_effectiveAt) : lurgiDateKey();
    final entries =
        ref.read(lurgiChemicalUsageForDayProvider(dayKey)).valueOrNull ?? [];
    if (value && entries.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Clear or request-void today’s entries before marking none.',
          ),
        ),
      );
      return;
    }
    try {
      await ref.read(lurgiServiceProvider).setNoneTodayFlags(
            dateKey: dayKey,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
            chemicalsNoneToday: value,
            chemicalsNoneReason: value ? 'No dosing today' : null,
            effectiveAt: adminStamp ? _effectiveAt : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? 'Marked no chemicals today.'
              : 'Cleared “none today”.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Effluent Chemicals');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Effluent Chemicals')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final emp = ref.watch(currentEmployeeProvider).valueOrNull;
    final canEditDate = role_utils.isAdmin(emp);
    final dayKey =
        canEditDate ? lurgiDateKey(_effectiveAt) : lurgiDateKey();
    final entriesAsync = ref.watch(lurgiChemicalUsageForDayProvider(dayKey));
    final periodAsync = ref.watch(lurgiPeriodChemicalUsageProvider);
    final dayEntries = entriesAsync.valueOrNull ?? [];
    final totals = LurgiChemicalDayTotals.fromEntries(dayEntries);
    final periodTotals = ref.watch(lurgiPeriodChemicalTotalsProvider);
    final settingsAsync = ref.watch(inkSettingsProvider);
    final periodFrom = settingsAsync.valueOrNull?.latestActiveCountDate;
    final round = ref.watch(lurgiRoundForDateProvider(dayKey)).valueOrNull;
    final noneToday = round?.chemicalsNoneToday ?? false;
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;
    final df = DateFormat('EEE d MMM HH:mm');
    final dayLabel = canEditDate && dayKey != lurgiDateKey()
        ? 'Selected day'
        : 'Today';
    if (_loadedDraft && !_draftBannerShown) {
      _draftBannerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft restored — unsaved entry kept'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Effluent Chemicals')),
      body: ListView(
        padding: ScreenInsets.symmetricScroll(context),
        children: [
          const LurgiOperatorNote(
            noteId: 'chemicals_multi_entry',
            message:
                'Add one entry per dose. Day total is the sum. Wrong row → '
                'Request void (desk voids on Pulse). Use “No dosing today” if idle.',
          ),
          LurgiPeriodBanner(
            periodFrom: periodFrom,
            settingsLoading: settingsAsync.isLoading,
          ),
          const SizedBox(height: 10),
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
              'Date: $dayKey · saved at current time · day total = sum of entries.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No dosing today'),
            subtitle: const Text('Marks intentional zero for the desk'),
            value: noneToday,
            onChanged: dayEntries.isNotEmpty && !noneToday
                ? null
                : (v) => _setNoneToday(v),
          ),
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
                    noneToday
                        ? '$dayLabel · none today ✓'
                        : '$dayLabel · ${totals.entryCount} entr${totals.entryCount == 1 ? 'y' : 'ies'} · ${_qty.format(totals.totalKg)} kg'
                            '${totals.voidRequestedCount > 0 ? ' · ${totals.voidRequestedCount} void pending' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: appColors.lurgiDark,
                    ),
                  ),
                  if (periodFrom != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Open period · ${periodTotals.entryCount} entr${periodTotals.entryCount == 1 ? 'y' : 'ies'} · ${_qty.format(periodTotals.totalKg)} kg',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!noneToday) ...[
            const SizedBox(height: 16),
            Text(
              'ADD USAGE',
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
                children: [
                  _kgField(_caustic, 'Caustic soda'),
                  _kgField(_hcl, 'Hydrochloric acid'),
                  _kgField(_salt, 'Sodium chloride'),
                  _kgField(_naccolaint, 'Naccolaint'),
                  TextFormField(
                    controller: _comments,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Comments (optional)',
                      border: OutlineInputBorder(),
                    ),
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
                    label: Text(_submitting ? 'Saving…' : 'Add entry'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            "TODAY'S ENTRIES",
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not load: $e'),
            data: (entries) {
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    noneToday
                        ? 'Marked none today — no doses logged.'
                        : 'No chemical entries yet today.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final e in entries) _entryCard(e, scheme),
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
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not load period: $e'),
            data: (entries) {
              final earlier =
                  entries.where((e) => e.dateKey != dayKey).toList();
              if (periodFrom == null && !settingsAsync.isLoading) {
                return Text(
                  'No active count period — history hidden.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                );
              }
              if (earlier.isEmpty) {
                return Text(
                  'No earlier chemical entries in this open period '
                  '(first page). See Period history for full list.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                );
              }
              return Column(
                children: [
                  for (final e in earlier) _entryCard(e, scheme, showDate: true),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _entryCard(
    LurgiChemicalUsage e,
    ColorScheme scheme, {
    bool showDate = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${_qty.format(e.totalKg)} kg total'
          '${e.voidRequested ? ' · void requested' : ''}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: e.voidRequested ? scheme.error : scheme.onSurface,
          ),
        ),
        subtitle: Text(
          [
            if (showDate)
              '${_day.format(e.recordedAt)} · ${_time.format(e.recordedAt)}'
            else
              _time.format(e.recordedAt),
            if (e.actorName.isNotEmpty) e.actorName,
            'C ${_qty.format(e.causticSodaKg)} · '
                'HCl ${_qty.format(e.hydrochloricAcidKg)} · '
                'NaCl ${_qty.format(e.sodiumChlorideKg)} · '
                'N ${_qty.format(e.naccolaintKg)}',
            if (e.comments != null) e.comments!,
            if (e.voidRequested && e.voidRequestReason != null)
              'Void reason: ${e.voidRequestReason}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: e.id == null || e.voidRequested
            ? null
            : IconButton(
                tooltip: 'Request void',
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => _requestVoid(e),
              ),
      ),
    );
  }

  Widget _kgField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'kg',
          border: const OutlineInputBorder(),
        ),
        validator: (v) {
          final t = (v ?? '').trim().replaceAll(',', '.');
          if (t.isEmpty) return null;
          final d = double.tryParse(t);
          if (d == null) return 'Invalid number';
          if (d < 0) return 'Must be ≥ 0';
          return null;
        },
      ),
    );
  }
}
