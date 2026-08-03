import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/impression_settings.dart';
import '../services/impression_service.dart';
import '../theme/app_theme.dart';
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_condition_chips.dart';
import '../widgets/impression_tip_banner.dart';

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
  String conditionCharge = 'OK';
  String conditionDischarge = 'OK';
  String? shaftNo;
  String? sleeveId;
  String? cycleId;
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
        'conditionCharge': u.conditionCharge,
        'conditionDischarge': u.conditionDischarge,
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
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return Scaffold(
      appBar: ImpressionAppBar(
        title: 'Daily ESA · ${_cfg.label}',
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _submit,
            child: const Text('Submit', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ImpressionTipBanner(
                  tipId: 'daily_esa',
                  text: ImpressionTipBanner.tips['daily_esa']!,
                ),
                Text(
                  'Charge: $charge · Discharge: $discharge',
                  style: TextStyle(fontSize: 13, color: onSurface),
                ),
                const SizedBox(height: 8),
                ...List.generate(8, (i) {
                  final u = _units[i];
                  final n = i + 1;
                  if (u.noEsa) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: scheme.surfaceContainerHighest,
                      child: ListTile(
                        title: Text('Unit $n', style: TextStyle(color: onSurface)),
                        subtitle: Text(
                          'Yellow — no ESA',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.75)),
                        ),
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
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: onSurface,
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Cleaned $charge',
                              style: TextStyle(color: onSurface),
                            ),
                            value: u.cleanedCharge,
                            onChanged: (v) => setState(() => u.cleanedCharge = v ?? false),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Cleaned $discharge',
                              style: TextStyle(color: onSurface),
                            ),
                            value: u.cleanedDischarge,
                            onChanged: (v) => setState(() => u.cleanedDischarge = v ?? false),
                          ),
                          ImpressionConditionChips(
                            label: 'Condition of $charge',
                            options: ImpressionConditionChips.esaChargeOptions,
                            value: u.conditionCharge,
                            onChanged: (v) => setState(() => u.conditionCharge = v),
                          ),
                          const SizedBox(height: 10),
                          ImpressionConditionChips(
                            label: 'Condition of $discharge',
                            options: ImpressionConditionChips.esaDischargeOptions,
                            value: u.conditionDischarge,
                            onChanged: (v) => setState(() => u.conditionDischarge = v),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _saving ? null : _submit,
                  child: const Text('Submit daily ESA'),
                ),
              ],
            ),
    );
  }
}
