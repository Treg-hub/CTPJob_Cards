import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/impression_settings.dart';
import '../services/impression_service.dart';

/// Real per-unit daily impression roller inspection (replaces stub submit).
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
  final condition = TextEditingController();
  final actionTaken = TextEditingController();
  bool get isOccupied => state == 'occupied';

  void dispose() {
    aSide.dispose();
    bSide.dispose();
    bladder.dispose();
    outletC.dispose();
    inletC.dispose();
    condition.dispose();
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
            'Attempt to drop pressure while running and note action. Save anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Edit')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save with flag')),
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
        'condition': u.condition.text.trim(),
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily IR · $label'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Date ${ImpressionService.todayDateKey()} · Max A/B ${_cfg.aSideBarMax} bar · bladder ${_cfg.bladderBarMax} bar',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Shift colour (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => _shiftColour = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 12),
                ...List.generate(8, (i) => _unitCard(i)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: const Text('Submit daily IR'),
                ),
              ],
            ),
    );
  }

  Widget _unitCard(int i) {
    final u = _units[i];
    final n = i + 1;
    if (!u.isOccupied) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Colors.orange.shade50,
        child: ListTile(
          title: Text('Unit $n'),
          subtitle: const Text('Awaiting install — N/A for IR'),
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
                color: over ? Colors.red.shade800 : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: u.aSide,
                    decoration: InputDecoration(
                      labelText: 'A-side bar',
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
                    decoration: const InputDecoration(
                      labelText: 'B-side bar',
                      border: OutlineInputBorder(),
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
                    decoration: const InputDecoration(
                      labelText: 'Bladder bar',
                      border: OutlineInputBorder(),
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
                      decoration: const InputDecoration(
                        labelText: 'Outlet °C (A)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: u.inletC,
                      decoration: const InputDecoration(
                        labelText: 'Inlet °C (B)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: u.condition,
              decoration: const InputDecoration(
                labelText: 'Condition / defects',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (over) ...[
              const SizedBox(height: 8),
              TextField(
                controller: u.actionTaken,
                decoration: const InputDecoration(
                  labelText: 'Action taken (drop pressure / planned change)',
                  border: OutlineInputBorder(),
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
