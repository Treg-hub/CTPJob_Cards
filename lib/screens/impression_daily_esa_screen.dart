import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/impression_settings.dart';
import '../services/impression_service.dart';

class ImpressionDailyEsaScreen extends StatefulWidget {
  final String pressId;
  final ImpressionSettings settings;

  const ImpressionDailyEsaScreen({
    super.key,
    required this.pressId,
    required this.settings,
  });

  @override
  State<ImpressionDailyEsaScreen> createState() => _ImpressionDailyEsaScreenState();
}

class _EsaUnit {
  bool noEsa = false;
  bool cleanedCharge = false;
  bool cleanedDischarge = false;
  final condCharge = TextEditingController();
  final condDischarge = TextEditingController();
  String? shaftNo;
  String? sleeveId;
  String? cycleId;

  void dispose() {
    condCharge.dispose();
    condDischarge.dispose();
  }
}

class _ImpressionDailyEsaScreenState extends State<ImpressionDailyEsaScreen> {
  final _units = List.generate(8, (_) => _EsaUnit());
  bool _loading = true;
  bool _saving = false;

  ImpressionPressConfig get _cfg =>
      widget.settings.presses[widget.pressId] ??
      ImpressionSettings.defaults.presses[widget.pressId]!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final u in _units) {
      u.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final noEsa = _cfg.noEsaUnits.toSet();
    final snap = await FirebaseFirestore.instance
        .collection('impression_unit_slots')
        .where('pressId', isEqualTo: widget.pressId)
        .get();
    for (var i = 0; i < 8; i++) {
      _units[i].noEsa = noEsa.contains(i + 1);
    }
    for (final d in snap.docs) {
      final m = d.data();
      final n = (m['unitNo'] as num?)?.toInt() ?? 0;
      if (n < 1 || n > 8) continue;
      _units[n - 1].shaftNo = m['shaftNo'] as String?;
      _units[n - 1].sleeveId = m['sleeveId'] as String?;
      _units[n - 1].cycleId = m['cycleId'] as String?;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    final units = <String, Map<String, dynamic>>{};
    for (var i = 0; i < 8; i++) {
      final u = _units[i];
      if (u.noEsa) continue;
      units['${i + 1}'] = {
        'cleanedCharge': u.cleanedCharge,
        'cleanedDischarge': u.cleanedDischarge,
        'conditionCharge': u.condCharge.text.trim(),
        'conditionDischarge': u.condDischarge.text.trim(),
        'shaftNo': u.shaftNo,
        'sleeveId': u.sleeveId,
        'cycleId': u.cycleId,
      };
    }
    setState(() => _saving = true);
    try {
      await ImpressionService.instance.submitDailyEsa(
        pressId: widget.pressId,
        dateKey: ImpressionService.todayDateKey(),
        units: units,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily ESA saved')),
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
    final charge = _cfg.esaChargeLabel;
    final discharge = _cfg.esaDischargeLabel;
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily ESA · ${_cfg.label}'),
        actions: [
          TextButton(onPressed: _saving || _loading ? null : _submit, child: const Text('Submit')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Charge: $charge · Discharge: $discharge',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ...List.generate(8, (i) {
                  final u = _units[i];
                  final n = i + 1;
                  if (u.noEsa) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('Unit $n'),
                        subtitle: const Text('Yellow — no ESA'),
                      ),
                    );
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unit $n · ${u.shaftNo ?? "—"} / ${u.sleeveId ?? "—"}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Cleaned $charge'),
                            value: u.cleanedCharge,
                            onChanged: (v) => setState(() => u.cleanedCharge = v ?? false),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Cleaned $discharge'),
                            value: u.cleanedDischarge,
                            onChanged: (v) => setState(() => u.cleanedDischarge = v ?? false),
                          ),
                          TextField(
                            controller: u.condCharge,
                            decoration: InputDecoration(
                              labelText: 'Condition $charge',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: u.condDischarge,
                            decoration: InputDecoration(
                              labelText: 'Condition $discharge',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                FilledButton(onPressed: _saving ? null : _submit, child: const Text('Submit daily ESA')),
              ],
            ),
    );
  }
}
