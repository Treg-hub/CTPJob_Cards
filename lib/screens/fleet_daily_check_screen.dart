import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_issue.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_daily_checklist_rows.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_reporter_widgets.dart';
import '../utils/screen_insets.dart';

enum _CheckMode { loading, start, done }

/// Pre-use daily safety check — verify machine safe before use; hour meter snapshot.
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
  final _scrollCtrl = ScrollController();

  StreamSubscription<FleetDailyCheck?>? _checkSub;

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
    final assetId = widget.asset.id;
    if (assetId != null) {
      _checkSub = _service.watchDailyCheck(assetId).listen(_onCheckUpdate);
    } else {
      _mode = _CheckMode.start;
    }
  }

  void _onCheckUpdate(FleetDailyCheck? check) {
    if (!mounted) return;
    final newMode =
        (check == null || !check.hasStart) ? _CheckMode.start : _CheckMode.done;
    setState(() {
      _todayCheck = check;
      _mode = newMode;
    });
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

  @override
  void dispose() {
    _checkSub?.cancel();
    _scrollCtrl.dispose();
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
              child: const Text('Save & notify mechanic'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  Future<FleetIssueSeverity?> _promptFaultSeverity() async {
    FleetIssueSeverity? selected = FleetIssueSeverity.medium;
    final result = await showDialog<FleetIssueSeverity>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final primary = theme.colorScheme.primary;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('How urgent is the problem?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'The mechanic will see this under To Fix.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: FleetIssueSeverity.values.map((s) {
                      final isSelected = selected == s;
                      final chipColor = s == FleetIssueSeverity.outOfService
                          ? theme.colorScheme.error
                          : primary;
                      return ChoiceChip(
                        label: Text(reporterSeverityLabel(s)),
                        selected: isSelected,
                        selectedColor: chipColor,
                        onSelected: (_) =>
                            setDialogState(() => selected = s),
                      );
                    }).toList(),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 12),
                    FleetReporterSeverityHint(severity: selected!),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
    return result;
  }

  String _issueDescription({
    required List<FleetDailyCheckItem> faultyItems,
    required String faultComment,
    String? generalComment,
  }) {
    final lines = <String>[
      'Daily safety check — items not verified safe:',
      ...faultyItems.map((i) => '• ${i.label}'),
      '',
      faultComment,
    ];
    if (generalComment != null && generalComment.isNotEmpty) {
      lines.addAll(['', 'Operator note: $generalComment']);
    }
    return lines.join('\n');
  }

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    if (emp == null) return;
    final actor = resolveWriteActor(emp)!;

    var items = List<FleetDailyCheckItem>.from(_items);
    final faultyItems =
        items.where((i) => !i.isOk || !i.reviewed).toList();

    String? faultComment;
    FleetIssueSeverity faultSeverity = FleetIssueSeverity.medium;
    if (faultyItems.isNotEmpty) {
      faultComment = await _promptFaultComment(faultyItems);
      if (faultComment == null) return;
      final severity = await _promptFaultSeverity();
      if (severity == null || !mounted) return;
      faultSeverity = severity;
      if (faultSeverity == FleetIssueSeverity.outOfService) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mark machine out of service?'),
            content: Text(
              '${widget.asset.name} cannot be used until the mechanic fixes it. '
              'Send this problem report?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send report'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
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
      _showMessage('Enter the hour meter reading.');
      return;
    }

    final generalComment = _commentCtrl.text.trim();
    final checkCommentParts = <String>[];
    if (generalComment.isNotEmpty) checkCommentParts.add(generalComment);
    if (faultComment != null) checkCommentParts.add('Faults: $faultComment');

    setState(() => _submitting = true);
    try {
      final hasFaulty = items.any((i) => i.isFaulty);
      final checkResult = await _service.createDailyCheckStartResilient(
        assetId: widget.asset.id!,
        assetName: widget.asset.name,
        assetTag: widget.asset.assetTag,
        driverClockNo: actor.clockNo,
        driverName: emp.name,
        department: emp.department,
        items: items,
        hourMeter: hourMeter,
        generalComment:
            checkCommentParts.isEmpty ? null : checkCommentParts.join('\n'),
      );

      if (hasFaulty && faultComment != null) {
        await _service.createIssueResilient(
          FleetIssue(
            assetId: widget.asset.id!,
            assetName: widget.asset.name,
            description: _issueDescription(
              faultyItems: faultyItems,
              faultComment: faultComment,
              generalComment:
                  generalComment.isEmpty ? null : generalComment,
            ),
            severity: faultSeverity,
            reportedByClockNo: actor.clockNo,
            reportedByName: actor.name,
            source: 'daily_check',
            dailyCheckId: checkResult.id,
          ),
        );
      }

      if (!mounted) return;
      final queued = checkResult.queuedOffline;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Check saved offline — will sync when connection returns.'
                : hasFaulty
                    ? 'Check saved. Problem sent to the mechanic.'
                    : 'Safety check complete. Machine cleared for use.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showMessage('Could not save check: $e');
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

    if (_loadingConfig || _mode == _CheckMode.loading) {
      return Scaffold(
        appBar: const FleetAppBar(title: 'Daily Safety Check'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final emp = currentEmployee;
    final now = DateTime.now();
    final timeFmt = DateFormat('dd MMM yyyy · HH:mm');

    final title = _mode == _CheckMode.done
        ? 'Check Complete'
        : 'Daily Safety Check';

    return Scaffold(
      appBar: FleetAppBar(title: title),
      bottomNavigationBar: _mode == _CheckMode.start
          ? SafeBottomBar(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _submitting ? 'Saving…' : 'Complete safety check',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )
          : null,
      body: ListView(
        controller: _scrollCtrl,
        primary: false,
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          ScreenInsets.scrollBottomFullScreen(
            context,
            extra: _mode == _CheckMode.start ? 88 : ScreenInsets.spacing,
          ),
        ),
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
              'recorded as faults and sent to the mechanic.',
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
                hintText: 'Any notes before using the machine',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hour meter *',
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
            ),
          ],

          if (_mode == _CheckMode.done && _todayCheck != null) ...[
            _buildDoneSummary(context, _todayCheck!),
            const SizedBox(height: 12),
            Text(
              'This machine was already checked today. '
              'Only one pre-use check per machine per day.',
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ],

        ],
      ),
    );
  }

  Widget _buildDoneSummary(BuildContext context, FleetDailyCheck check) {
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
              'Checked by: ${start.driverName} (#${start.driverClockNo})',
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
            if (start.at != null) ...[
              const SizedBox(height: 4),
              Text(
                'Time: ${timeFmt.format(start.at!)} · ${start.hourMeter} h',
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
            ],
            if (start.generalComment != null &&
                start.generalComment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                start.generalComment!,
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
            ],
            if (check.hasFaultyItems) ...[
              const SizedBox(height: 8),
              Text(
                '${check.faultyCount} item(s) flagged — mechanic notified',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (start.items.isNotEmpty) ...[
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