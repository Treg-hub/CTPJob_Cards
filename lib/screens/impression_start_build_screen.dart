import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../services/impression_service.dart';
import '../theme/app_theme.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_tip_banner.dart';

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
  /// Visible stamp; managers/admin may adjust. Floor roles always "now" on open.
  DateTime _effectiveAt = DateTime.now();

  bool get _canEditTimestamp =>
      role_utils.canEditImpressionTimestamp(currentEmployee);

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

  Future<void> _pickTimestamp() async {
    if (!_canEditTimestamp) return;
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null && mounted) setState(() => _effectiveAt = dt);
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
        // Always send so managers' edits stick; CF ignores for non-managers.
        effectiveAt: _effectiveAt,
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

  Widget _buildTimestampField(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy · HH:mm');
    final label = 'Date & time: ${df.format(_effectiveAt)}';
    if (_canEditTimestamp) {
      return OutlinedButton.icon(
        onPressed: _pickTimestamp,
        icon: const Icon(Icons.event),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          alignment: Alignment.centerLeft,
        ),
      );
    }
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: ImpressionAppBar(title: 'Start build · ${widget.pressId}'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ImpressionTipBanner(
            tipId: 'start_build',
            text: ImpressionTipBanner.tips['start_build']!,
          ),
          _buildTimestampField(context),
          if (_canEditTimestamp)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'Managers and admins can adjust the date and time.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            const SizedBox(height: 8),
          const SizedBox(height: 4),
          TextField(
            controller: _shaft,
            decoration: const InputDecoration(
              labelText: 'Shaft (Roller No.) *',
              border: OutlineInputBorder(),
            ),
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
              child: Text(_preferredHint!, style: TextStyle(color: kBrandOrange, fontWeight: FontWeight.w600)),
            ),
          if (_preferredHint?.contains('rematch') == true) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _rematchReason,
              decoration: const InputDecoration(labelText: 'Rematch reason', border: OutlineInputBorder()),
            ),
          ],
          const Divider(height: 24),
          Text(
            'Mechanical (control sheet)',
            style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
          ),
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
            style: FilledButton.styleFrom(
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.black,
            ),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Start build'),
          ),
        ],
      ),
    );
  }
}
