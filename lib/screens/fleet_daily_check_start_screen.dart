import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_form_fields.dart';
import 'fleet_report_wizard_screen.dart';

/// Full 14-item daily start check before using a machine.
class FleetDailyCheckStartScreen extends ConsumerStatefulWidget {
  const FleetDailyCheckStartScreen({super.key, required this.asset});

  final FleetAsset asset;

  @override
  ConsumerState<FleetDailyCheckStartScreen> createState() =>
      _FleetDailyCheckStartScreenState();
}

class _FleetDailyCheckStartScreenState
    extends ConsumerState<FleetDailyCheckStartScreen> {
  final _service = FleetService();
  final _hourCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  FleetDailyChecklistConfig _config = FleetDailyChecklistConfig.defaults;
  List<FleetDailyCheckItem> _items = [];
  bool _loading = true;
  bool _submitting = false;
  bool _instructionsExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    final hours = widget.asset.currentMachineHours;
    if (hours != null) {
      _hourCtrl.text = hours % 1 == 0
          ? hours.toStringAsFixed(0)
          : hours.toStringAsFixed(1);
    }
  }

  Future<void> _loadConfig() async {
    final config = await _service.getDailyChecklistConfig();
    if (!mounted) return;
    setState(() {
      _config = config.items.isEmpty
          ? FleetDailyChecklistConfig.defaults
          : config;
      _items = _config.items
          .map((i) => FleetDailyCheckItem(id: i.id, label: i.label))
          .toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  bool get _allReviewed => _items.every((i) => i.reviewed);

  bool get _hasFaulty => _items.any((i) => i.isFaulty);

  void _toggleItem(int index, String result) {
    setState(() {
      _items[index] = _items[index].copyWith(result: result, reviewed: true);
    });
  }

  Future<void> _submit() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (!_allReviewed) {
      _showMessage('Please review all ${ _items.length } checklist items.');
      return;
    }

    final hourText = _hourCtrl.text.trim();
    final hourMeter = double.tryParse(hourText.replaceAll(',', '.'));
    if (hourMeter == null) {
      _showMessage('Enter the hour meter reading at start.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _service.createDailyCheckStartResilient(
        assetId: widget.asset.id!,
        assetName: widget.asset.name,
        assetTag: widget.asset.assetTag,
        driverClockNo: emp.clockNo,
        driverName: emp.name,
        department: emp.department,
        items: _items,
        hourMeter: hourMeter,
        generalComment: _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
      );

      if (!mounted) return;

      final queued = result.queuedOffline;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Check saved offline — will sync when connection returns.'
                : _hasFaulty
                    ? 'Check saved. Some items marked faulty — mechanic may follow up.'
                    : 'Daily check complete. You can use the machine.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: _hasFaulty
              ? SnackBarAction(
                  label: 'Report problem',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => FleetReportWizardScreen(
                          preSelectedAsset: widget.asset,
                        ),
                      ),
                    );
                  },
                )
              : null,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        _showMessage('Could not save check: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final emp = currentEmployee;
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final now = DateTime.now();
    final timeFmt = DateFormat('dd MMM yyyy · HH:mm');

    if (_loading) {
      return Scaffold(
        appBar: const FleetAppBar(title: 'Daily Check'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const FleetAppBar(title: 'Daily Check — Start'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: (_submitting || !_allReviewed) ? null : _submit,
            icon: _submitting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_submitting ? 'Saving…' : 'Complete start check'),
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
          if (_config.instructions.isNotEmpty) ...[
            Card(
              color: Colors.amber.shade50,
              child: ExpansionTile(
                initiallyExpanded: _instructionsExpanded,
                onExpansionChanged: (v) =>
                    setState(() => _instructionsExpanded = v),
                title: const Text(
                  'Instructions & REMEMBER',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                children: _config.instructions
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Text(line, style: const TextStyle(fontSize: 13)),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          _InfoRow(label: 'Reg (machine)', value: widget.asset.name),
          _InfoRow(label: 'Driver', value: emp?.name ?? '—'),
          _InfoRow(label: 'Co/No', value: emp?.clockNo ?? '—'),
          _InfoRow(label: 'Date / time', value: timeFmt.format(now)),
          const SizedBox(height: 16),

          Text(
            'Check each item — tap OK when verified (defaults to Faulty until you confirm).',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: 8),

          ...List.generate(_items.length, (index) {
            final item = _items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: colors.cardSurface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${item.id}. ${item.label}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'ok',
                            label: Text('OK'),
                            icon: Icon(Icons.check, size: 16),
                          ),
                          ButtonSegment(
                            value: 'faulty',
                            label: Text('Faulty'),
                            icon: Icon(Icons.warning_amber, size: 16),
                          ),
                        ],
                        selected: {item.result},
                        onSelectionChanged: (s) => _toggleItem(index, s.first),
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          if (_config.footerNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            ..._config.footerNotes.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  n,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Text(
            'General comment (optional)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _commentCtrl,
            maxLines: 2,
            decoration: fleetDropdownDecoration(
              hintText: 'Notes at start of shift',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Hour meter at start *',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (widget.asset.currentMachineHours != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last recorded: ${widget.asset.currentMachineHours!.toStringAsFixed(1)} h',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
          const SizedBox(height: 6),
          TextField(
            controller: _hourCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fleetDropdownDecoration(hintText: 'e.g. 10450.5'),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).appColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}