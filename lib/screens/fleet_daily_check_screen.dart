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
import '../widgets/fleet_daily_checklist_rows.dart';
import '../widgets/fleet_form_fields.dart';
import 'fleet_report_wizard_screen.dart';

enum _CheckMode { loading, start, end, done, blocked }

/// Unified daily safety check — pre-use start, end-of-shift close, hour meters.
class FleetDailyCheckScreen extends ConsumerStatefulWidget {
  const FleetDailyCheckScreen({super.key, required this.asset});

  final FleetAsset asset;

  @override
  ConsumerState<FleetDailyCheckScreen> createState() =>
      _FleetDailyCheckScreenState();
}

class _FleetDailyCheckScreenState extends ConsumerState<FleetDailyCheckScreen> {
  final _service = FleetService();
  final _hourCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  FleetDailyChecklistConfig _config = FleetDailyChecklistConfig.defaults;
  List<FleetDailyCheckItem> _items = [];
  FleetDailyCheck? _todayCheck;
  _CheckMode _mode = _CheckMode.loading;
  bool _loadingConfig = true;
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
      _loadingConfig = false;
    });
  }

  void _applyCheck(FleetDailyCheck? check) {
    final emp = currentEmployee;
    _todayCheck = check;

    if (check == null || !check.hasStart) {
      _mode = _CheckMode.start;
      return;
    }
    if (check.hasEnd) {
      _mode = _CheckMode.done;
      return;
    }
    if (emp != null && check.start?.driverClockNo == emp.clockNo) {
      _mode = _CheckMode.end;
      return;
    }
    _mode = _CheckMode.blocked;
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _toggleItem(int index, bool checked) {
    setState(() {
      _items[index] = _items[index].copyWith(
        result: checked ? 'ok' : 'faulty',
        reviewed: checked,
      );
    });
  }

  Future<String?> _promptFaultComment(List<FleetDailyCheckItem> faulty) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colors = Theme.of(ctx).appColors;
        return AlertDialog(
          title: const Text('Items not verified safe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'These checklist items were left unchecked. Describe the problem '
                  'so the mechanic can follow up.',
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
                const SizedBox(height: 12),
                ...faulty.map(
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${i.label}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: fleetDropdownDecoration(
                    hintText: 'What is wrong? (required)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () {
                final text = ctrl.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx, text);
              },
              child: const Text('Save as faulty'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _submitStart() async {
    final emp = currentEmployee;
    if (emp == null) return;

    var items = List<FleetDailyCheckItem>.from(_items);
    final unchecked = items.where((i) => !i.isOk || !i.reviewed).toList();

    String? faultComment;
    if (unchecked.isNotEmpty) {
      faultComment = await _promptFaultComment(unchecked);
      if (faultComment == null) return;
      items = items
          .map(
            (i) => (!i.isOk || !i.reviewed)
                ? i.copyWith(result: 'faulty', reviewed: true)
                : i,
          )
          .toList();
    }

    final hourText = _hourCtrl.text.trim();
    final hourMeter = double.tryParse(hourText.replaceAll(',', '.'));
    if (hourMeter == null) {
      _showMessage('Enter the hour meter reading at start.');
      return;
    }

    final generalParts = <String>[];
    final baseComment = _commentCtrl.text.trim();
    if (baseComment.isNotEmpty) generalParts.add(baseComment);
    if (faultComment != null) generalParts.add('Faults: $faultComment');

    setState(() => _submitting = true);
    try {
      final hasFaulty = items.any((i) => i.isFaulty);
      final result = await _service.createDailyCheckStartResilient(
        assetId: widget.asset.id!,
        assetName: widget.asset.name,
        assetTag: widget.asset.assetTag,
        driverClockNo: emp.clockNo,
        driverName: emp.name,
        department: emp.department,
        items: items,
        hourMeter: hourMeter,
        generalComment:
            generalParts.isEmpty ? null : generalParts.join('\n'),
      );

      if (!mounted) return;
      final queued = result.queuedOffline;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Check saved offline — will sync when connection returns.'
                : hasFaulty
                    ? 'Check saved. Unsafe items recorded — mechanic may follow up.'
                    : 'Safety check complete. Machine cleared for use.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: hasFaulty
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
      if (mounted) _showMessage('Could not save check: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitEnd() async {
    final emp = currentEmployee;
    if (emp == null || _todayCheck?.start == null) return;

    final start = _todayCheck!.start!;
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
        checkDocId: _todayCheck!.id!,
        assetId: _todayCheck!.assetId,
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
                : 'Shift ended for ${widget.asset.name}.',
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
    if (widget.asset.id == null) {
      return Scaffold(
        appBar: const FleetAppBar(title: 'Daily Safety Check'),
        body: const Center(child: Text('Invalid machine.')),
      );
    }

    return StreamBuilder<FleetDailyCheck?>(
      stream: _service.watchDailyCheck(widget.asset.id!),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            appBar: const FleetAppBar(title: 'Daily Safety Check'),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (_mode == _CheckMode.loading || snap.hasData) {
          _applyCheck(snap.data);
        }

        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final emp = currentEmployee;
    final now = DateTime.now();
    final timeFmt = DateFormat('dd MMM yyyy · HH:mm');

    if (_loadingConfig) {
      return Scaffold(
        appBar: const FleetAppBar(title: 'Daily Safety Check'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final title = switch (_mode) {
      _CheckMode.start => 'Daily Safety Check',
      _CheckMode.end => 'End Shift',
      _CheckMode.done => 'Check Complete',
      _CheckMode.blocked => 'Check In Progress',
      _CheckMode.loading => 'Daily Safety Check',
    };

    final canSubmitStart = _mode == _CheckMode.start && !_submitting;
    final canSubmitEnd = _mode == _CheckMode.end && !_submitting;

    return Scaffold(
      appBar: FleetAppBar(title: title),
      bottomNavigationBar: (_mode == _CheckMode.start || _mode == _CheckMode.end)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : _mode == _CheckMode.start
                          ? _submitStart
                          : _submitEnd,
                  icon: _submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Icon(_mode == _CheckMode.end
                          ? Icons.logout
                          : Icons.check_circle_outline),
                  label: Text(
                    _submitting
                        ? 'Saving…'
                        : _mode == _CheckMode.end
                            ? 'Complete end shift'
                            : 'Complete safety check',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_mode == _CheckMode.start) ...[
            if (_config.instructions.isNotEmpty) ...[
              Card(
                color: colors.cardSurface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
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
                          child: Text(
                            line,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textMuted,
                            ),
                          ),
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
              'Tick each item when verified safe. Unchecked items will be '
              'recorded as faults at submit.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
            const SizedBox(height: 8),
            FleetDailyChecklistRows(
              items: _items,
              onToggle: _toggleItem,
            ),
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: fleetDropdownDecoration(hintText: 'e.g. 10450.5'),
              enabled: canSubmitStart || canSubmitEnd,
            ),
          ],

          if (_mode == _CheckMode.end && _todayCheck?.start != null) ...[
            _buildStartSummary(context, _todayCheck!),
            const SizedBox(height: 20),
            const Text(
              'Hour meter at end *',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _hourCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: fleetDropdownDecoration(
                hintText:
                    'Must be ≥ ${_todayCheck!.start!.hourMeter.toStringAsFixed(1)}',
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
          ],

          if (_mode == _CheckMode.done && _todayCheck != null) ...[
            _buildStartSummary(context, _todayCheck!),
            if (_todayCheck!.end != null) ...[
              const SizedBox(height: 16),
              Card(
                color: colors.cardSurface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Shift closed',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'End: ${_todayCheck!.end!.hourMeter.toStringAsFixed(1)} h'
                        '${_todayCheck!.hoursUsed != null ? ' · ${_todayCheck!.hoursUsed!.toStringAsFixed(1)} h used' : ''}',
                        style: TextStyle(fontSize: 13, color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Today\'s safety check and hour meter are recorded.',
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ],

          if (_mode == _CheckMode.blocked && _todayCheck?.start != null) ...[
            _buildStartSummary(context, _todayCheck!),
            const SizedBox(height: 16),
            Text(
              'This machine was checked in by ${_todayCheck!.start!.driverName}. '
              'Only that driver can end the shift.',
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildStartSummary(BuildContext context, FleetDailyCheck check) {
    final start = check.start!;
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final timeFmt = DateFormat('dd MMM · HH:mm');

    return Card(
      color: colors.cardSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              check.assetName,
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
            if (check.hasFaultyItems) ...[
              const SizedBox(height: 8),
              Text(
                '${check.faultyCount} item(s) flagged at start',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_mode == _CheckMode.done && start.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              FleetDailyChecklistRows(
                items: start.items,
                onToggle: (_, __) {},
                readOnly: true,
              ),
            ],
          ],
        ),
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