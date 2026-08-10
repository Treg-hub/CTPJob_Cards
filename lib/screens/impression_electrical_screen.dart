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
  /// Defaults to FAIL so operators must deliberately choose PASS.
  /// PASS = full ESA (any unit); FAIL = yellow units only. No separate ESA dropdown.
  bool _pass = false;
  bool _saving = false;
  DateTime _effectiveAt = DateTime.now();
  String? _performedByClock = currentEmployee?.clockNo;

  bool get _canEditTimestamp =>
      role_utils.canEditImpressionTimestamp(currentEmployee);
  bool get _canEditActor =>
      role_utils.canEditImpressionActors(currentEmployee);

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

  Future<void> _pickTimestamp() async {
    if (!_canEditTimestamp) return;
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null && mounted) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit() async {
    if (!_pass) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save as electrical FAIL?'),
          content: const Text(
            'This assembly will still go to spares, but may only be installed on yellow (no-ESA) units. Continue?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save FAIL · yellow only')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      // PASS → any unit (full ESA). FAIL → yellow units only. No extra choice.
      final esa = _pass ? 'full' : 'yellow_only';
      await ImpressionService.instance.completeElectrical(
        cycleId: widget.cycleId,
        pass: _pass,
        esaSuitability: esa,
        electrical: {
          'pass': _pass,
          'esaSuitability': esa,
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
        effectiveAt: _effectiveAt,
        performedByClock: _canEditActor ? _performedByClock : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pass
                ? 'Electrical PASS · OK for any unit — ready as spare'
                : 'Electrical FAIL · yellow units only — added to spares',
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
    final d = widget.cycleData;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final press = ImpressionFormat.press(d['pressId']?.toString());
    return Scaffold(
      appBar: ImpressionAppBar(
        title: 'Electrical · ${d['cycleNo'] ?? widget.cycleId}',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ImpressionTipBanner(
            tipId: 'electrical',
            text: ImpressionTipBanner.tips['electrical']!,
          ),
          _buildTimestampField(context),
          if (_canEditTimestamp)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Managers and admins can adjust the date and time.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            const SizedBox(height: 8),
          Text(
            'Shaft ${d['shaftNo'] ?? '—'}  ·  Sleeve ${d['sleeveId'] ?? '—'}  ·  $press',
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
          ),
          if (_canEditActor) ...[
            const SizedBox(height: 12),
            ImpressionActorPicker(
              role: ImpressionActorRole.electrical,
              selectedClock: _performedByClock,
              onChanged: (e) => setState(() => _performedByClock = e?.clockNo),
              label: 'Tested by (electrical)',
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Conductive resistance cold (mΩ)',
            style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Two rows — left / centre / right',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          _row3(_condL1, _condC1, _condR1, 'Left', 'Centre', 'Right'),
          const SizedBox(height: 6),
          _row3(_condL2, _condC2, _condR2, 'Left', 'Centre', 'Right'),
          const SizedBox(height: 16),
          Text(
            'Insulation resistance (GΩ)',
            style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Two rows — left / right',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          _row2(_insL1, _insR1, 'Left', 'Right'),
          const SizedBox(height: 6),
          _row2(_insL2, _insR2, 'Left', 'Right'),
          const SizedBox(height: 12),
          TextField(
            controller: _comments,
            style: TextStyle(color: onSurface),
            decoration: const InputDecoration(
              labelText: 'Comments',
              hintText: 'e.g. Passed · tested by…',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          ImpressionPassFailToggle(
            pass: _pass,
            title: 'Electrical result',
            failHint:
                'FAIL = yellow (no-ESA) units only. Spare can still be used on those units.',
            passHint: 'PASS = acceptable for any unit on this press.',
            onChanged: (v) => setState(() => _pass = v),
          ),
          Card(
            color: _pass
                ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
            child: ListTile(
              leading: Icon(
                _pass ? Icons.check_circle_outline : Icons.warning_amber,
                color: _pass ? const Color(0xFF2E7D32) : null,
              ),
              title: Text(_pass ? 'OK for any unit' : 'Yellow units only'),
              subtitle: Text(
                _pass
                    ? 'Full ESA — can install on any unit of this press.'
                    : 'Install only on yellow (no-ESA) units. No override to ESA units.',
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                : Text(
                    _pass
                        ? 'Submit electrical PASS'
                        : 'Save FAIL · yellow units only',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row3(TextEditingController a, TextEditingController b, TextEditingController c, String la, String lb, String lc) {
    return Row(children: [
      Expanded(child: TextField(controller: a, decoration: InputDecoration(labelText: la, border: const OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
      const SizedBox(width: 6),
      Expanded(child: TextField(controller: b, decoration: InputDecoration(labelText: lb, border: const OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
      const SizedBox(width: 6),
      Expanded(child: TextField(controller: c, decoration: InputDecoration(labelText: lc, border: const OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
    ]);
  }

  Widget _row2(TextEditingController a, TextEditingController b, String la, String lb) {
    return Row(children: [
      Expanded(child: TextField(controller: a, decoration: InputDecoration(labelText: la, border: const OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
      const SizedBox(width: 6),
      Expanded(child: TextField(controller: b, decoration: InputDecoration(labelText: lb, border: const OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
    ]);
  }
}
