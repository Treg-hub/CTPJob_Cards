import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../services/impression_service.dart';
import '../theme/app_theme.dart';
import '../utils/impression_format.dart';
import '../utils/ink_pickers.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/impression_actor_picker.dart';
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_pass_fail_toggle.dart';
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
  /// Defaults to FAIL so operators must deliberately choose PASS.
  bool _pass = false;
  bool _saving = false;
  String? _preferredHint;
  /// Visible stamp; managers/admin may adjust. Floor roles always "now" on open.
  DateTime _effectiveAt = DateTime.now();
  /// Who built the roller (managers/admin may pick staff; floor = self).
  /// Same person as paper “Bearings fitted by”.
  String? _performedByClock = currentEmployee?.clockNo;

  bool get _canEditTimestamp =>
      role_utils.canEditImpressionTimestamp(currentEmployee);
  bool get _canEditActor =>
      role_utils.canEditImpressionActors(currentEmployee);

  @override
  void initState() {
    super.initState();
    // Floor: pre-fill builder name as self. Managers fill via picker or type.
    final me = currentEmployee?.name.trim() ?? '';
    if (me.isNotEmpty) {
      _bearingsBy.text = me;
    }
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the shaft (roller) number')),
      );
      return;
    }
    if (!_unnumbered && _sleeve.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter sleeve number, or tick unnumbered (UNN)')),
      );
      return;
    }
    if (_bearingsBy.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter who built the roller (bearings fitted by)'),
        ),
      );
      return;
    }
    if (!_pass) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save as FAIL?'),
          content: const Text(
            'Mechanical is still set to FAIL. Electrical will not start until this assembly passes. Save as mechanical fail?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save as FAIL')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    final rematch = _preferredHint?.contains('rematch') == true;
    if (rematch && _rematchReason.text.trim().isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rematch sleeve to shaft?'),
          content: const Text(
            'This sleeve was preferred on a different shaft. Continue with this pairing?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
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
        // Paper field = who built the roller (same person as mechanical actor name).
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
        // Manager/admin: staff list clock. Floor: always self (CF ignores pick).
        performedByClock: _canEditActor ? _performedByClock : null,
      );
      if (!mounted) return;
      final resultLabel = _pass ? 'PASS' : 'FAIL';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Build ${_pass ? "started" : "saved as fail"} · ${res['cycleNo']} · sleeve ${res['sleeveId']} ($resultLabel)',
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
    final pressLabel = ImpressionFormat.press(widget.pressId);
    return Scaffold(
      appBar: ImpressionAppBar(title: 'Start build · $pressLabel'),
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
              labelText: 'Shaft (roller No.) *',
              hintText: 'e.g. M4588',
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
            title: const Text('Sleeve unnumbered (system assigns UNN)'),
            subtitle: const Text('Tick if the sleeve has no number yet'),
            contentPadding: EdgeInsets.zero,
          ),
          if (!_unnumbered)
            TextField(
              controller: _sleeve,
              decoration: const InputDecoration(
                labelText: 'Sleeve No. *',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _checkPreferred(),
            ),
          if (_preferredHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _preferredHint!,
                style: const TextStyle(color: kBrandOrange, fontWeight: FontWeight.w600),
              ),
            ),
          if (_preferredHint?.contains('rematch') == true) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _rematchReason,
              decoration: const InputDecoration(
                labelText: 'Why rematch this sleeve/shaft?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const Divider(height: 24),
          Text(
            'Mechanical control sheet',
            style: TextStyle(fontWeight: FontWeight.bold, color: onSurface, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Fill measurements from the paper control sheet. Empty fields are allowed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _length,
            decoration: const InputDecoration(
              labelText: 'Length (mm)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          Text('Shore hardness', style: TextStyle(fontWeight: FontWeight.w600, color: onSurface)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: _shoreL, decoration: const InputDecoration(labelText: 'Left', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _shoreM, decoration: const InputDecoration(labelText: 'Middle', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _shoreR, decoration: const InputDecoration(labelText: 'Right', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _sizeDia,
            decoration: const InputDecoration(
              labelText: 'Size / diameter (mm)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          SwitchListTile(
            title: const Text('Roller balancing OK'),
            subtitle: Text(_balancing ? 'Yes — balancing OK' : 'No — balancing not OK'),
            value: _balancing,
            onChanged: (v) => setState(() => _balancing = v),
            contentPadding: EdgeInsets.zero,
          ),
          Text('Roller diameter (mm)', style: TextStyle(fontWeight: FontWeight.w600, color: onSurface)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: _diaL, decoration: const InputDecoration(labelText: 'Left', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _diaM, decoration: const InputDecoration(labelText: 'Middle', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _diaR, decoration: const InputDecoration(labelText: 'Right', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _roughness,
            decoration: const InputDecoration(
              labelText: 'Roughness (µm)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          Text(
            'Built by',
            style: TextStyle(fontWeight: FontWeight.w700, color: onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Same as paper “Bearings fitted by” — the person who built the roller.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          if (_canEditActor)
            ImpressionActorPicker(
              role: ImpressionActorRole.mechanical,
              selectedClock: _performedByClock,
              onChanged: (e) => setState(() {
                _performedByClock = e?.clockNo;
                if (e != null && e.name.trim().isNotEmpty) {
                  _bearingsBy.text = e.name.trim();
                }
              }),
              label: 'Built by (staff list)',
            ),
          TextField(
            controller: _bearingsBy,
            decoration: InputDecoration(
              labelText: _canEditActor
                  ? 'Built by / bearings fitted by *'
                  : 'Built by / bearings fitted by (name) *',
              hintText: 'Name on control sheet',
              border: const OutlineInputBorder(),
              helperText: _canEditActor
                  ? 'Pick from list above or type the name from the paper sheet'
                  : 'You are recorded as the builder (edit name only if needed)',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comments,
            decoration: const InputDecoration(
              labelText: 'Comments',
              hintText: 'e.g. Pressure tested, O-rings changed…',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          ImpressionPassFailToggle(
            pass: _pass,
            title: 'Mechanical result',
            failHint: 'Defaults to FAIL. Tap PASS only when the mechanical check is good.',
            passHint: 'PASS — Electrical can test this assembly next.',
            onChanged: (v) => setState(() => _pass = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _pass ? kBrandOrange : Theme.of(context).colorScheme.error,
              foregroundColor: _pass ? Colors.black : Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _pass ? Colors.black : Colors.white,
                    ),
                  )
                : Text(_pass ? 'Start build (PASS)' : 'Save mechanical FAIL'),
          ),
        ],
      ),
    );
  }
}
