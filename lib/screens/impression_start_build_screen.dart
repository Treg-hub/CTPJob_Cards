import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/impression_service.dart';

/// Mechanical control sheet + start build.
class ImpressionStartBuildScreen extends StatefulWidget {
  final String pressId;

  const ImpressionStartBuildScreen({super.key, required this.pressId});

  @override
  State<ImpressionStartBuildScreen> createState() => _ImpressionStartBuildScreenState();
}

class _ImpressionStartBuildScreenState extends State<ImpressionStartBuildScreen> {
  final _shaft = TextEditingController();
  final _sleeve = TextEditingController();
  final _length = TextEditingController();
  final _shoreL = TextEditingController();
  final _shoreM = TextEditingController();
  final _shoreR = TextEditingController();
  final _sizeDia = TextEditingController();
  final _diaL = TextEditingController();
  final _diaM = TextEditingController();
  final _diaR = TextEditingController();
  final _roughness = TextEditingController();
  final _comments = TextEditingController();
  final _bearingsBy = TextEditingController();
  final _rematchReason = TextEditingController();
  bool _unnumbered = false;
  bool _balancing = true;
  bool _pass = true;
  bool _saving = false;
  String? _preferredHint;

  @override
  void dispose() {
    for (final c in [
      _shaft, _sleeve, _length, _shoreL, _shoreM, _shoreR, _sizeDia,
      _diaL, _diaM, _diaR, _roughness, _comments, _bearingsBy, _rematchReason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkPreferred() async {
    if (_unnumbered || _sleeve.text.trim().isEmpty) {
      setState(() => _preferredHint = null);
      return;
    }
    final id = _sleeve.text.trim().toUpperCase();
    final doc = await FirebaseFirestore.instance.collection('impression_sleeves').doc(id).get();
    if (!doc.exists) {
      setState(() => _preferredHint = null);
      return;
    }
    final pref = doc.data()?['preferredShaftNo'] as String?;
    final shaft = _shaft.text.trim().toUpperCase();
    if (pref != null && pref.isNotEmpty && shaft.isNotEmpty && pref != shaft) {
      setState(() => _preferredHint = 'Preferred shaft was $pref (rematch)');
    } else {
      setState(() => _preferredHint = pref != null ? 'Preferred shaft: $pref' : null);
    }
  }

  Future<void> _submit() async {
    if (_shaft.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shaft required')));
      return;
    }
    if (!_unnumbered && _sleeve.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sleeve or UNN required')));
      return;
    }
    final rematch = _preferredHint?.contains('rematch') == true;
    if (rematch && _rematchReason.text.trim().isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rematch sleeve/shaft'),
          content: const Text('This sleeve was preferred on another shaft. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rematch')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final mechanical = {
        'pass': _pass,
        'length': _length.text.trim(),
        'shoreHardness': {
          'left': _shoreL.text.trim(),
          'middle': _shoreM.text.trim(),
          'right': _shoreR.text.trim(),
        },
        'sizeDiameterMm': _sizeDia.text.trim(),
        'rollerBalancing': _balancing,
        'rollerDiameter': {
          'left': _diaL.text.trim(),
          'middle': _diaM.text.trim(),
          'right': _diaR.text.trim(),
        },
        'roughnessUm': _roughness.text.trim(),
        'comments': _comments.text.trim(),
        'bearingsFittedBy': _bearingsBy.text.trim(),
      };
      final res = await ImpressionService.instance.startBuild(
        shaftNo: _shaft.text.trim(),
        pressId: widget.pressId,
        sleeveId: _unnumbered ? null : _sleeve.text.trim(),
        unnumbered: _unnumbered,
        rematch: rematch,
        rematchReason: _rematchReason.text.trim().isEmpty ? null : _rematchReason.text.trim(),
        mechanical: mechanical,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cycle ${res['cycleNo']} · sleeve ${res['sleeveId']}')),
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
    return Scaffold(
      appBar: AppBar(title: Text('Start build · ${widget.pressId}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _shaft,
            decoration: const InputDecoration(labelText: 'Shaft (Roller No.) *', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => _checkPreferred(),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _unnumbered,
            onChanged: (v) => setState(() {
              _unnumbered = v ?? false;
              _preferredHint = null;
            }),
            title: const Text('Sleeve unnumbered (UNN)'),
            contentPadding: EdgeInsets.zero,
          ),
          if (!_unnumbered)
            TextField(
              controller: _sleeve,
              decoration: const InputDecoration(labelText: 'Sleeve No. *', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _checkPreferred(),
            ),
          if (_preferredHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_preferredHint!, style: TextStyle(color: Colors.orange.shade800)),
            ),
          if (_preferredHint?.contains('rematch') == true) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _rematchReason,
              decoration: const InputDecoration(labelText: 'Rematch reason', border: OutlineInputBorder()),
            ),
          ],
          const Divider(height: 24),
          const Text('Mechanical (control sheet)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _length, decoration: const InputDecoration(labelText: 'Length', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _shoreL, decoration: const InputDecoration(labelText: 'Shore L', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _shoreM, decoration: const InputDecoration(labelText: 'Shore M', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _shoreR, decoration: const InputDecoration(labelText: 'Shore R', border: OutlineInputBorder(), isDense: true))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _sizeDia, decoration: const InputDecoration(labelText: 'Size (diameter) mm', border: OutlineInputBorder())),
          SwitchListTile(
            title: const Text('Roller balancing OK'),
            value: _balancing,
            onChanged: (v) => setState(() => _balancing = v),
            contentPadding: EdgeInsets.zero,
          ),
          Row(children: [
            Expanded(child: TextField(controller: _diaL, decoration: const InputDecoration(labelText: 'Dia L', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _diaM, decoration: const InputDecoration(labelText: 'Dia M', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _diaR, decoration: const InputDecoration(labelText: 'Dia R', border: OutlineInputBorder(), isDense: true))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _roughness, decoration: const InputDecoration(labelText: 'Roughness µm', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _bearingsBy, decoration: const InputDecoration(labelText: 'Bearings fitted by', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _comments, decoration: const InputDecoration(labelText: 'Comments', border: OutlineInputBorder()), maxLines: 2),
          SwitchListTile(
            title: const Text('Mechanical pass'),
            value: _pass,
            onChanged: (v) => setState(() => _pass = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const CircularProgressIndicator() : const Text('Start build'),
          ),
        ],
      ),
    );
  }
}
