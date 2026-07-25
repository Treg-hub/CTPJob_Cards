import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/lurgi_daily_round.dart';
import '../providers/current_employee_provider.dart';
import '../providers/lurgi_provider.dart';
import '../utils/ink_pickers.dart';
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/lurgi_operator_note.dart';

/// Standalone overhead tank dip — used for month-end Lurgi toloul sum.
class LurgiOverheadTankScreen extends ConsumerStatefulWidget {
  const LurgiOverheadTankScreen({super.key});

  @override
  ConsumerState<LurgiOverheadTankScreen> createState() =>
      _LurgiOverheadTankScreenState();
}

class _LurgiOverheadTankScreenState
    extends ConsumerState<LurgiOverheadTankScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qty = NumberFormat('#,##0.##');
  late final TextEditingController _litres;
  var _submitting = false;
  DateTime _effectiveAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _litres = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedFromRound());
  }

  @override
  void dispose() {
    _litres.dispose();
    super.dispose();
  }

  String get _dateKey => lurgiDateKey(_effectiveAt);

  Future<void> _seedFromRound() async {
    final round = await ref.read(lurgiServiceProvider).fetchRound(_dateKey);
    if (!mounted) return;
    if (round?.overheadTankLitres != null) {
      _litres.text = _qty.format(round!.overheadTankLitres);
    } else {
      _litres.clear();
    }
    setState(() {});
  }

  Future<void> _pickDay() async {
    if (!role_utils.isAdmin(currentEmployee)) return;
    final picked = await pickInkDateTime(context, _effectiveAt);
    if (picked == null || !mounted) return;
    setState(() => _effectiveAt = picked);
    await _seedFromRound();
  }

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate()) return;
    final raw = _litres.text.trim().replaceAll(',', '');
    final litres = double.tryParse(raw);
    if (litres == null || litres < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid non-negative litres reading')),
      );
      return;
    }

    final emp = resolveWriteActor(ref.read(currentEmployeeProvider).valueOrNull);
    if (emp == null) return;
    final isAdmin =
        role_utils.isAdmin(emp) || role_utils.isAdmin(currentEmployee);
    setState(() => _submitting = true);
    try {
      await ref.read(lurgiServiceProvider).saveOverheadTank(
            dateKey: _dateKey,
            litres: litres,
            actorClockNo: emp.clockNo,
            actorName: emp.name,
            effectiveAt: isAdmin ? _effectiveAt : null,
          );
      ref.invalidate(lurgiTodayRoundProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Overhead tank saved for $_dateKey')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
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
      return const OffSiteBlockedScreen(title: 'Overhead Tank');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Overhead Tank')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final roundAsync = ref.watch(lurgiTodayRoundProvider);
    final todayKey = lurgiDateKey();
    final showingToday = _dateKey == todayKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overhead Tank'),
        actions: [
          if (role_utils.isAdmin(currentEmployee))
            IconButton(
              tooltip: 'Pick date',
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today_outlined),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            ScreenInsets.scrollBottomFullScreen(context),
          ),
          children: [
            const LurgiOperatorNote(
              noteId: 'overhead_tank_count',
              message:
                  'Dip the overhead (pressroom) toloul tank. This reading is used '
                  'with Tank 1–3 on month-end count (Pulse). Not part of the daily '
                  'morning tank walk.',
            ),
            Text(
              showingToday ? 'Today · $_dateKey' : 'Date · $_dateKey',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (showingToday)
              roundAsync.when(
                data: (r) {
                  if (r?.overheadTankLitres == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Saved: ${_qty.format(r!.overheadTankLitres)} L'
                      '${r.overheadTankByName != null ? ' · ${r.overheadTankByName}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _litres,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Overhead tank (litres)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = (v ?? '').trim().replaceAll(',', '');
                if (t.isEmpty) return 'Required';
                final n = double.tryParse(t);
                if (n == null || n < 0) return 'Invalid litres';
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_submitting ? 'Saving…' : 'Save dip'),
            ),
          ],
        ),
      ),
    );
  }
}
