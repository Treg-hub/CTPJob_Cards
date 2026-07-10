import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/employee.dart';
import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import '../services/firestore_service.dart';
import '../services/work_report_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart';
import '../utils/work_report_period_utils.dart';
import '../utils/work_report_soft_lock.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';

class WorkReportJobLinesScreen extends ConsumerStatefulWidget {
  const WorkReportJobLinesScreen({
    super.key,
    required this.subjectClockNo,
    required this.periodKey,
  });

  final String subjectClockNo;
  final String periodKey;

  @override
  ConsumerState<WorkReportJobLinesScreen> createState() =>
      _WorkReportJobLinesScreenState();
}

class _WorkReportJobLinesScreenState
    extends ConsumerState<WorkReportJobLinesScreen> {
  bool _refreshing = false;
  final _firestoreService = FirestoreService();
  WorkReportPeriod? _period;

  bool get _editable {
    final settings =
        ref.read(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;
    return WorkReportPeriodUtils.isPeriodEditable(
      widget.periodKey,
      editablePeriodsBack: settings.editablePeriodsBack,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
  }

  bool get _isAdminEdit =>
      isAdmin(currentEmployee) &&
      currentEmployee?.clockNo != widget.subjectClockNo;

  @override
  void initState() {
    super.initState();
    _loadPeriod();
  }

  Future<void> _loadPeriod() async {
    final service = ref.read(workReportServiceProvider);
    final p = await service
        .watchPeriod(widget.subjectClockNo, widget.periodKey)
        .first
        .timeout(const Duration(seconds: 10));
    if (mounted) setState(() => _period = p);
  }

  Future<void> _refresh(WorkReportService service, Employee subject) async {
    if (currentEmployee == null) return;
    setState(() => _refreshing = true);
    try {
      final settings =
          ref.read(workReportSettingsProvider).valueOrNull ??
              WorkReportSettings.defaults;
      final added = await service.refreshJobLines(
        clockNo: widget.subjectClockNo,
        periodKey: widget.periodKey,
        settings: settings,
        subject: subject,
        actor: currentEmployee!,
      );
      await _loadPeriod();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added job card(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _saveLine(
    WorkReportService service,
    WorkReportJobLine line, {
    required String? prevHours,
    required String? prevSummary,
  }) async {
    if (currentEmployee == null) return;
    final ok = await confirmWorkReportEditAfterPdf(context, period: _period);
    if (!ok) return;
    try {
      await service.upsertJobLine(
        line: line,
        actor: currentEmployee!,
        isAdminEdit: _isAdminEdit,
        previousHours: prevHours,
        previousSummary: prevSummary,
      );
      await _loadPeriod();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(workReportServiceProvider);
    return Scaffold(
      appBar: CtpAppBar(
        title: 'Job cards — ${WorkReportPeriodUtils.periodLabel(widget.periodKey)}',
      ),
      body: StreamBuilder(
        stream: service.watchJobLines(widget.subjectClockNo, widget.periodKey),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lines = snapshot.data!;
          return Column(
            children: [
              if (!_editable)
                const MaterialBanner(
                  content: Text('This period is read-only.'),
                  leading: Icon(Icons.lock),
                  actions: [SizedBox.shrink()],
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: !_editable || _refreshing
                        ? null
                        : () async {
                            final emp = await _firestoreService
                                .getEmployee(widget.subjectClockNo);
                            if (emp != null) await _refresh(service, emp);
                          },
                    icon: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_refreshing ? 'Refreshing…' : 'Refresh job list'),
                  ),
                ),
              ),
              Expanded(
                child: lines.isEmpty
                    ? const Center(
                        child: Text(
                          'No job cards yet.\nTap Refresh to load from your assignments.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        padding: ScreenInsets.listPadding(
                          context,
                          horizontal: 12,
                          top: 0,
                        ),
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          return _JobLineTile(
                            line: lines[index],
                            editable: _editable,
                            onSave: (updated, prevH, prevS) =>
                                _saveLine(service, updated,
                                    prevHours: prevH, prevSummary: prevS),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _JobLineTile extends StatefulWidget {
  const _JobLineTile({
    required this.line,
    required this.editable,
    required this.onSave,
  });

  final WorkReportJobLine line;
  final bool editable;
  final void Function(
    WorkReportJobLine updated,
    String? prevHours,
    String? prevSummary,
  ) onSave;

  @override
  State<_JobLineTile> createState() => _JobLineTileState();
}

class _JobLineTileState extends State<_JobLineTile> {
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _summaryCtrl;
  bool _expanded = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _hoursCtrl = TextEditingController(
      text: widget.line.hours == 0 ? '' : widget.line.hours.toString(),
    );
    _summaryCtrl = TextEditingController(text: widget.line.billingSummary);
    _hoursCtrl.addListener(_markDirty);
    _summaryCtrl.addListener(_markDirty);
  }

  void _markDirty() {
    final hours = double.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final dirty = hours != widget.line.hours ||
        _summaryCtrl.text.trim() != widget.line.billingSummary;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  @override
  void didUpdateWidget(covariant _JobLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.id != widget.line.id ||
        (!_dirty &&
            (oldWidget.line.hours != widget.line.hours ||
                oldWidget.line.billingSummary != widget.line.billingSummary))) {
      _hoursCtrl.text =
          widget.line.hours == 0 ? '' : widget.line.hours.toString();
      _summaryCtrl.text = widget.line.billingSummary;
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    final hours = double.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final updated = WorkReportJobLine(
      id: widget.line.id,
      clockNo: widget.line.clockNo,
      periodKey: widget.line.periodKey,
      jobCardId: widget.line.jobCardId,
      jobCardNumber: widget.line.jobCardNumber,
      hours: hours,
      billingSummary: _summaryCtrl.text.trim(),
      correctiveActionSnapshot: widget.line.correctiveActionSnapshot,
      jobMeta: widget.line.jobMeta,
      orphan: widget.line.orphan,
      createdAt: widget.line.createdAt,
      updatedAt: widget.line.updatedAt,
    );
    widget.onSave(
      updated,
      widget.line.hours.toString(),
      widget.line.billingSummary,
    );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final scheme = Theme.of(context).colorScheme;
    final orphanBg = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    return Card(
      color: line.orphan ? orphanBg : null,
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Text(
          line.jobCardNumber > 0
              ? '#${line.jobCardNumber} — ${line.jobMeta.type}'
              : line.jobMeta.type,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          [
            line.jobMeta.locationLabel,
            if (_dirty) '• Unsaved',
          ].where((s) => s.trim().isNotEmpty).join(' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _dirty ? scheme.primary : null,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (line.orphan)
                  Text(
                    'No longer matches inclusion rules (hours kept).',
                    style: TextStyle(
                      color: Theme.of(context).appColors.statusOpen,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _hoursCtrl,
                  enabled: widget.editable,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onEditingComplete: _commit,
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Work done (from job card)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(
                  line.correctiveActionSnapshot.trim().isEmpty
                      ? '—'
                      : line.correctiveActionSnapshot,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _summaryCtrl,
                  enabled: widget.editable,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Billing summary (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onEditingComplete: _commit,
                ),
                if (widget.editable) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _dirty ? _commit : null,
                      child: Text(_dirty ? 'Save changes' : 'Saved'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
