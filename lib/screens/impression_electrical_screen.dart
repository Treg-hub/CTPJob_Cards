import 'package:flutter/material.dart';

import '../services/impression_service.dart';

class ImpressionElectricalScreen extends StatefulWidget {
  final String cycleId;
  final Map<String, dynamic> cycleData;

  const ImpressionElectricalScreen({
    super.key,
    required this.cycleId,
    required this.cycleData,
  });

  @override
  State<ImpressionElectricalScreen> createState() => _ImpressionElectricalScreenState();
}

class _ImpressionElectricalScreenState extends State<ImpressionElectricalScreen> {
  final _condL1 = TextEditingController();
  final _condC1 = TextEditingController();
  final _condR1 = TextEditingController();
  final _condL2 = TextEditingController();
  final _condC2 = TextEditingController();
  final _condR2 = TextEditingController();
  final _insL1 = TextEditingController();
  final _insR1 = TextEditingController();
  final _insL2 = TextEditingController();
  final _insR2 = TextEditingController();
  final _comments = TextEditingController();
  bool _pass = true;
  String _esa = 'full';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _condL1, _condC1, _condR1, _condL2, _condC2, _condR2,
      _insL1, _insR1, _insL2, _insR2, _comments,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ImpressionService.instance.completeElectrical(
        cycleId: widget.cycleId,
        pass: _pass,
        esaSuitability: _pass ? _esa : 'unsuitable',
        electrical: {
          'pass': _pass,
          'conductiveResistanceCold': {
            'row1': {'left': _condL1.text, 'centre': _condC1.text, 'right': _condR1.text},
            'row2': {'left': _condL2.text, 'centre': _condC2.text, 'right': _condR2.text},
          },
          'insulationResistance': {
            'row1': {'left': _insL1.text, 'right': _insR1.text},
            'row2': {'left': _insL2.text, 'right': _insR2.text},
          },
          'comments': _comments.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Electrical saved')));
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
    final d = widget.cycleData;
    return Scaffold(
      appBar: AppBar(title: Text('Electrical · ${d['cycleNo'] ?? widget.cycleId}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${d['shaftNo']} / ${d['sleeveId']} · ${d['pressId']}'),
          const SizedBox(height: 12),
          const Text('Conductive resistance cold (mΩ)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _row3(_condL1, _condC1, _condR1, 'L', 'C', 'R'),
          const SizedBox(height: 6),
          _row3(_condL2, _condC2, _condR2, 'L', 'C', 'R'),
          const SizedBox(height: 12),
          const Text('Insulation resistance (GΩ)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _row2(_insL1, _insR1, 'L', 'R'),
          const SizedBox(height: 6),
          _row2(_insL2, _insR2, 'L', 'R'),
          const SizedBox(height: 12),
          TextField(
            controller: _comments,
            decoration: const InputDecoration(labelText: 'Comments', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          SwitchListTile(
            title: const Text('Pass'),
            value: _pass,
            onChanged: (v) => setState(() {
              _pass = v;
              if (!v) _esa = 'unsuitable';
            }),
            contentPadding: EdgeInsets.zero,
          ),
          if (_pass)
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _esa,
              items: const [
                DropdownMenuItem(value: 'full', child: Text('Full ESA OK')),
                DropdownMenuItem(value: 'yellow_only', child: Text('Yellow units only')),
              ],
              onChanged: (v) => setState(() => _esa = v ?? 'full'),
              decoration: const InputDecoration(labelText: 'ESA suitability', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _submit, child: const Text('Submit electrical')),
        ],
      ),
    );
  }

  Widget _row3(TextEditingController a, TextEditingController b, TextEditingController c, String la, String lb, String lc) {
    return Row(children: [
      Expanded(child: TextField(controller: a, decoration: InputDecoration(labelText: la, border: const OutlineInputBorder(), isDense: true))),
      const SizedBox(width: 6),
      Expanded(child: TextField(controller: b, decoration: InputDecoration(labelText: lb, border: const OutlineInputBorder(), isDense: true))),
      const SizedBox(width: 6),
      Expanded(child: TextField(controller: c, decoration: InputDecoration(labelText: lc, border: const OutlineInputBorder(), isDense: true))),
    ]);
  }

  Widget _row2(TextEditingController a, TextEditingController b, String la, String lb) {
    return Row(children: [
      Expanded(child: TextField(controller: a, decoration: InputDecoration(labelText: la, border: const OutlineInputBorder(), isDense: true))),
      const SizedBox(width: 6),
      Expanded(child: TextField(controller: b, decoration: InputDecoration(labelText: lb, border: const OutlineInputBorder(), isDense: true))),
    ]);
  }
}
