import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_daily_check.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_form_fields.dart';

/// Lighter end-of-shift screen — stop hours + optional comment.
class FleetDailyCheckEndScreen extends StatefulWidget {
  const FleetDailyCheckEndScreen({super.key, required this.check});

  final FleetDailyCheck check;

  @override
  State<FleetDailyCheckEndScreen> createState() =>
      _FleetDailyCheckEndScreenState();
}

class _FleetDailyCheckEndScreenState extends State<FleetDailyCheckEndScreen> {
  final _service = FleetService();
  final _hourCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _hourCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final emp = currentEmployee;
    if (emp == null) return;

    final start = widget.check.start;
    if (start == null) {
      _showMessage('This check has no start record.');
      return;
    }

    final hourText = _hourCtrl.text.trim();
    final endHour = double.tryParse(hourText.replaceAll(',', '.'));
    if (endHour == null) {
      _showMessage('Enter the hour meter reading at end of shift.');
      return;
    }
    if (endHour < start.hourMeter) {
      _showMessage(
        'End reading must be at least the start reading (${start.hourMeter}).',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _service.completeDailyCheckEndResilient(
        checkDocId: widget.check.id!,
        assetId: widget.check.assetId,
        endHourMeter: endHour,
        startHourMeter: start.hourMeter,
        comment: _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
        driverClockNo: emp.clockNo,
        driverName: emp.name,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedOffline
                ? 'End shift saved offline — will sync when connection returns.'
                : 'Shift ended for ${widget.check.assetName}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showMessage('Could not save: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.check.start!;
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final timeFmt = DateFormat('dd MMM · HH:mm');

    return Scaffold(
      appBar: const FleetAppBar(title: 'End Shift'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.logout),
            label: Text(_submitting ? 'Saving…' : 'Complete end shift'),
            style: FilledButton.styleFrom(
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: colors.cardSurface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.check.assetName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Driver: ${start.driverName} (#${start.driverClockNo})',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                  if (start.at != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Started: ${timeFmt.format(start.at!)} · ${start.hourMeter} h',
                      style: TextStyle(fontSize: 13, color: colors.textMuted),
                    ),
                  ],
                  if (widget.check.hasFaultyItems) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${widget.check.faultyCount} item(s) marked faulty at start',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Hour meter at end *',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _hourCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fleetDropdownDecoration(
              hintText: 'Must be ≥ ${start.hourMeter}',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'End comment (optional)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: fleetDropdownDecoration(
              hintText: 'Anything to note at end of shift',
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}