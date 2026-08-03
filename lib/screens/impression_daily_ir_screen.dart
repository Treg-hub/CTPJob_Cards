import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/impression_settings.dart';
import '../services/impression_service.dart';
import '../theme/app_theme.dart';
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_condition_chips.dart';
import '../widgets/impression_tip_banner.dart';

/// Real per-unit daily impression roller inspection.
class ImpressionDailyIrScreen extends StatefulWidget {
  final String pressId;
  final ImpressionSettings settings;

  const ImpressionDailyIrScreen({
    super.key,
    required this.pressId,
    required this.settings,
  });

  @override
  State<ImpressionDailyIrScreen> createState() => _ImpressionDailyIrScreenState();
}

class _UnitIr {
  String? shaftNo;
  String? sleeveId;
  String? cycleId;
  String state = 'awaiting_install';
  final aSide = TextEditingController();
  final bSide = TextEditingController();
  final bladder = TextEditingController();
  final outletC = TextEditingController();
  final inletC = TextEditingController();
  String condition = 'OK';
  final actionTaken = TextEditingController();
  bool get isOccupied => state == 'occupied';

  void dispose() {
    aSide.dispose();
    bSide.dispose();
    bladder.dispose();
    outletC.dispose();
    inletC.dispose();
    actionTaken.dispose();
  }
}

class _ImpressionDailyIrScreenState extends State<ImpressionDailyIrScreen> {
  final _units = List.generate(8, (_) => _UnitIr());
  bool _loading = true;
  bool _saving = false;
  String? _shiftColour;

  ImpressionPressConfig get _cfg =>
      widget.settings.presses[widget.pressId] ??
      ImpressionSettings.defaults.presses[widget.pressId]!;

  bool get _isBadenia => widget.pressId == 'badenia';

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    for (final u in _units) {
      u.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSlots() async {
    final snap = await FirebaseFirestore.instance
        .collection('impression_unit_slots')
        .where('pressId', isEqualTo: widget.pressId)
        .get();
    for (final d in snap.docs) {
      final m = d.data();
      final n = (m['unitNo'] as num?)?.toInt() ?? 0;
      if (n < 1 || n > 8) continue;
      final u = _units[n - 1];
      u.state = (m['state'] as String?) ?? 'awaiting_install';
      u.shaftNo = m['shaftNo'] as String?;
      u.sleeveId = m['sleeveId'] as String?;
      u.cycleId = m['cycleId'] as String?;
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _overMax(_UnitIr u) {
    final a = double.tryParse(u.aSide.text);
    final b = double.tryParse(u.bSide.text);
    final bl = double.tryParse(u.bladder.text);
    if (a != null && a > _cfg.aSideBarMax) return true;
    if (b != null && b > _cfg.bSideBarMax) return true;
    if (bl != null && bl > _cfg.bladderBarMax) return true;
    return false;
  }

  Future<void> _submit() async {
    final overUnits = <int>[];
    for (var i = 0; i < 8; i++) {
      final u = _units[i];
      if (!u.isOccupied) continue;
      if (u.aSide.text.trim().isEmpty ||
          u.bSide.text.trim().isEmpty ||
          u.bladder.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unit ${i + 1}: enter A/B/bladder pressures')),
        );
        return;
      }
      if (u.condition.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unit ${i + 1}: select a condition')),
        );
        return;
      }
      if (_overMax(u)) overUnits.add(i + 1);
    }

    if (overUnits.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pressure over max'),
          content: Text(
            'Unit(s) ${overUnits.join(", ")} above max '
            '(A/B ${_cfg.aSideBarMax}, bladder ${_cfg.bladderBarMax}). '
            'Note the action taken. Save anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Edit')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save with flag'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    final units = <String, Map<String, dynamic>>{};
    for (var i = 0; i < 8; i++) {
      final u = _units[i];
      if (!u.isOccupied) continue;
      units['${i + 1}'] = {
        'shaftNo': u.shaftNo,
        'sleeveId': u.sleeveId,
        'cycleId': u.cycleId,
        'aSideBar': double.tryParse(u.aSide.text),
        'bSideBar': double.tryParse(u.bSide.text),
        'bladderBar': double.tryParse(u.bladder.text),
        if (_isBadenia) 'outletC': double.tryParse(u.outletC.text),
        if (_isBadenia) 'inletC': double.tryParse(u.inletC.text),
        'condition': u.condition.trim(),
        'actionTaken': u.actionTaken.text.trim().isEmpty
            ? null
            : u.actionTaken.text.trim(),
      };
    }

    setState(() => _saving = true);
    try {
      final res = await ImpressionService.instance.submitDailyIr(
        pressId: widget.pressId,
        dateKey: ImpressionService.todayDateKey(),
        units: units,
        shiftColour: _shiftColour,
      );
      if (!mounted) return;
      final esc = res['escalations'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            esc is List && esc.isNotEmpty
                ? 'IR saved · pressure streak escalation sent'
                : 'Daily IR saved',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _cfg.label;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return Scaffold(
      appBar: ImpressionAppBar(
        title: 'Daily IR · $label',
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Submit', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ImpressionTipBanner(
                  tipId: 'daily_ir',
                  text: ImpressionTipBanner.tips['daily_ir']!,
                ),
                Text(
                  'Date ${ImpressionService.todayDateKey()} · Max A/B ${_cfg.aSideBarMax} bar · bladder ${_cfg.bladderBarMax} bar',
                  style: TextStyle(fontSize: 13, color: onSurface),
                ),
                const SizedBox(height: 8),
                TextField(
                  style: TextStyle(color: onSurface),
                  decoration: InputDecoration(
                    labelText: 'Shift colour (optional)',
                    labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => _shiftColour = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 12),
                ...List.generate(8, (i) => _unitCard(i, onSurface, scheme)),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _saving ? null : _submit,
                  child: const Text('Submit daily IR'),
                ),
              ],
            ),
    );
  }

  Widget _unitCard(int i, Color onSurface, ColorScheme scheme) {
    final u = _units[i];
    final n = i + 1;
    if (!u.isOccupied) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: scheme.surfaceContainerHighest,
        child: ListTile(
          title: Text('Unit $n', style: TextStyle(color: onSurface)),
          subtitle: Text(
            'Awaiting install — N/A for IR',
            style: TextStyle(color: onSurface.withValues(alpha: 0.75)),
          ),
        ),
      );
    }
    final over = _overMax(u);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unit $n · ${u.shaftNo ?? "—"} / ${u.sleeveId ?? "—"}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: over ? scheme.error : onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: u.aSide,
                    style: TextStyle(color: onSurface),
                    decoration: InputDecoration(
                      labelText: 'A-side bar',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: (double.tryParse(u.aSide.text) ?? 0) > _cfg.aSideBarMax
                          ? 'Over max'
                          : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: u.bSide,
                    style: TextStyle(color: onSurface),
                    decoration: InputDecoration(
                      labelText: 'B-side bar',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: u.bladder,
                    style: TextStyle(color: onSurface),
                    decoration: InputDecoration(
                      labelText: 'Bladder bar',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_isBadenia) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: u.outletC,
                      style: TextStyle(color: onSurface),
                      decoration: InputDecoration(
                        labelText: 'Outlet °C (A)',
                        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: u.inletC,
                      style: TextStyle(color: onSurface),
                      decoration: InputDecoration(
                        labelText: 'Inlet °C (B)',
                        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ImpressionConditionChips(
              label: 'Condition of impression roller',
              options: ImpressionConditionChips.rollerOptions,
              value: u.condition,
              onChanged: (v) => setState(() => u.condition = v),
            ),
            if (over) ...[
              const SizedBox(height: 8),
              TextField(
                controller: u.actionTaken,
                style: TextStyle(color: onSurface),
                decoration: InputDecoration(
                  labelText: 'Action taken (drop pressure / planned change)',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
