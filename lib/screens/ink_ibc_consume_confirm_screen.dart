import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/persona_audit.dart';
import '../utils/ink_pickers.dart';
import '../utils/screen_insets.dart';
import '../utils/user_facing_error.dart';

/// Full-screen confirm step after scan or manual IBC pick on Consume IBC.
class InkIbcConsumeConfirmScreen extends ConsumerStatefulWidget {
  const InkIbcConsumeConfirmScreen({
    super.key,
    required this.ibc,
    required this.tolulItemCode,
    required this.colourLabel,
  });

  final InkIbc ibc;
  final String? tolulItemCode;
  final String colourLabel;

  @override
  ConsumerState<InkIbcConsumeConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcConsumeConfirmScreen> {
  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM yyyy HH:mm');

  final _washCtrl = TextEditingController();
  bool _useCustomTime = false;
  DateTime _customAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _washCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomTime() async {
    final dt = await pickInkDateTime(context, _customAt);
    if (dt != null) setState(() => _customAt = dt);
  }

  DateTime get _effectiveAt => _useCustomTime ? _customAt : DateTime.now();

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    final tolul = widget.tolulItemCode;
    if (tolul == null) return;
    final wash = double.tryParse(_washCtrl.text.trim()) ?? 0;
    if (wash < 0) return;

    if (!guardPersonaSubmit(context)) return;
    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      final allowed =
          await confirmClosedPeriodOverride(context, ref, _effectiveAt);
      if (!allowed) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      await ref.read(inkServiceProvider).transferIbc(
            ibc: widget.ibc,
            tolulItemCode: tolul,
            washLitres: wash,
            effectiveAt: _effectiveAt,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(
              e,
              actionFallback:
                  'Could not consume this IBC. Check your connection and try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ibc = widget.ibc;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm consumption'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _submitting ? null : () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          ScreenInsets.scrollBottomFullScreen(context),
        ),
        children: [
          Icon(Icons.propane_tank_outlined, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'IBC ${ibc.ibcNumber}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.colourLabel} · ${_qty.format(ibc.kg)} kg',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (ibc.chargeNumber != null) ...[
            const SizedBox(height: 4),
            Text(
              'Charge ${ibc.chargeNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 28),
          TextField(
            controller: _washCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Toloul used to wash',
              suffixText: 'LTS',
              helperText: 'Leave blank if no wash was used',
            ),
          ),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('When consumed',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (!_useCustomTime) ...[
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Now (${_df.format(DateTime.now())})',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() {
                          _useCustomTime = true;
                          _customAt = DateTime.now();
                        }),
                        child: const Text('Different time?'),
                      ),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      onPressed: _pickCustomTime,
                      icon: const Icon(Icons.event),
                      label: Text(_df.format(_customAt)),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _useCustomTime = false),
                      child: const Text('Use now instead'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.tolulItemCode == null) ...[
            const SizedBox(height: 12),
            Text(
              'No toloul stock item found — wash cannot be recorded.',
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_submitting || widget.tolulItemCode == null)
                ? null
                : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Consume IBC'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}