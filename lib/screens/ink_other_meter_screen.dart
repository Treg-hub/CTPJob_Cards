import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';

/// Phase 1h — Other-meter capture. Factory toloul meters (consumption/recovery)
/// that do NOT affect Ink Factory stock are recorded here for reporting only —
/// written to `ink_other_meter_logs`, never the ledger.
class InkOtherMeterScreen extends ConsumerStatefulWidget {
  const InkOtherMeterScreen({super.key});

  @override
  ConsumerState<InkOtherMeterScreen> createState() => _State();
}

class _State extends ConsumerState<InkOtherMeterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _readingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _readingCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _date);
    if (dt != null) setState(() => _date = dt);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final allowed = await confirmClosedPeriodOverride(context, ref, _date);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).writeOtherMeterLog(
            label: _labelCtrl.text.trim(),
            reading: double.parse(_readingCtrl.text.trim()),
            readingDate: _date,
            actorClockNo: emp?.clockNo,
            actorName: emp?.name,
            notes: _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reading recorded (report-only).')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Other Meter Reading')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Meter / label'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the meter name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _readingCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Reading'),
              validator: (v) =>
                  double.tryParse((v ?? '').trim()) == null ? 'Enter a number' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text('Date: ${df.format(_date)}'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  alignment: Alignment.centerLeft),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('Record reading'),
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}
