import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../constants/ink_toloul.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../models/ink_tank_level.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/presence_gating.dart';
import '../utils/screen_insets.dart';

/// Record tank dips and edit capacity / low thresholds.
class InkTankLevelsScreen extends ConsumerStatefulWidget {
  const InkTankLevelsScreen({super.key});

  @override
  ConsumerState<InkTankLevelsScreen> createState() =>
      _InkTankLevelsScreenState();
}

class _InkTankLevelsScreenState extends ConsumerState<InkTankLevelsScreen> {
  static final _qty = NumberFormat('#,##0.##');

  final Map<String, TextEditingController> _balanceCtrls = {};
  final Map<String, TextEditingController> _capacityCtrls = {};
  final Map<String, TextEditingController> _lowCtrls = {};
  bool _seeded = false;
  bool _savingDips = false;
  bool _savingSettings = false;

  @override
  void dispose() {
    for (final c in _balanceCtrls.values) {
      c.dispose();
    }
    for (final c in _capacityCtrls.values) {
      c.dispose();
    }
    for (final c in _lowCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureControllers(List<InkTankLevel> tanks) {
    for (final t in tanks) {
      _balanceCtrls.putIfAbsent(
        t.itemCode,
        () => TextEditingController(text: _qty.format(t.balance)),
      );
      _capacityCtrls.putIfAbsent(
        t.itemCode,
        () => TextEditingController(text: _qty.format(t.capacity)),
      );
      _lowCtrls.putIfAbsent(
        t.itemCode,
        () => TextEditingController(text: _qty.format(t.lowThreshold)),
      );
    }
    if (!_seeded && tanks.isNotEmpty) {
      _seeded = true;
      for (final t in tanks) {
        _balanceCtrls[t.itemCode]!.text = t.balance.toString();
        _capacityCtrls[t.itemCode]!.text = t.capacity.toString();
        _lowCtrls[t.itemCode]!.text = t.lowThreshold.toString();
      }
    }
  }

  double? _parse(String raw) {
    final t = raw.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _submitDips(List<InkTankLevel> tanks) async {
    final balances = <String, double>{};
    for (final t in tanks) {
      final v = _parse(_balanceCtrls[t.itemCode]?.text ?? '');
      if (v == null || v < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a valid level for ${t.displayName}')),
        );
        return;
      }
      balances[t.itemCode] = v;
    }
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    setState(() => _savingDips = true);
    try {
      await ref.read(inkServiceProvider).submitTankDips(
            balancesByItem: balances,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tank levels recorded.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save levels: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingDips = false);
    }
  }

  Future<void> _submitSettings(List<InkTankLevel> tanks) async {
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    setState(() => _savingSettings = true);
    try {
      final svc = ref.read(inkServiceProvider);
      for (final t in tanks) {
        final cap = _parse(_capacityCtrls[t.itemCode]?.text ?? '');
        final low = _parse(_lowCtrls[t.itemCode]?.text ?? '');
        if (cap == null || cap <= 0 || low == null || low < 0) {
          throw StateError('Check capacity and low for ${t.displayName}');
        }
        await svc.updateTankSettings(
          itemCode: t.itemCode,
          capacity: cap,
          lowThreshold: low,
          actorClockNo: emp?.clockNo ?? '',
          actorName: emp?.name ?? '',
        );
        // Keep legacy toloul config in sync when editing toloul low.
        if (t.itemCode == kToloulItemCode) {
          await svc.updateToloulFactoryLowThreshold(low);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capacity and low levels saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Tank levels');
    }

    final tanksAsync = ref.watch(inkTankLevelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tank levels')),
      body: tanksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load tanks: $e')),
        data: (tanks) {
          _ensureControllers(tanks);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              ScreenInsets.scrollBottomFullScreen(context),
            ),
            children: [
              Text(
                'Record levels',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Physical dip / sight-glass. Overwrites the live estimate. '
                'Mon & Fri morning with meters; Toloul mid-week as needed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final t in tanks) ...[
                _DipRow(
                  tank: t,
                  balanceCtrl: _balanceCtrls[t.itemCode]!,
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _savingDips ? null : () => _submitDips(tanks),
                child: _savingDips
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save tank readings'),
              ),
              const SizedBox(height: 28),
              Text(
                'Capacity & low levels',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Capacity drives % full on Ink Home. Low turns the card red.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final t in tanks) ...[
                _SettingsRow(
                  tank: t,
                  capacityCtrl: _capacityCtrls[t.itemCode]!,
                  lowCtrl: _lowCtrls[t.itemCode]!,
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed:
                    _savingSettings ? null : () => _submitSettings(tanks),
                child: _savingSettings
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save capacity & lows'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DipRow extends StatelessWidget {
  const _DipRow({required this.tank, required this.balanceCtrl});

  final InkTankLevel tank;
  final TextEditingController balanceCtrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            tank.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: TextField(
            controller: balanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Level (${tank.unit})',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.tank,
    required this.capacityCtrl,
    required this.lowCtrl,
  });

  final InkTankLevel tank;
  final TextEditingController capacityCtrl;
  final TextEditingController lowCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tank.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: capacityCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Capacity (${tank.unit})',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: lowCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Low (${tank.unit})',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
