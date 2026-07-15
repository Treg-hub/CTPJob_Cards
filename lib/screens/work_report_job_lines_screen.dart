import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
    required String? prevWorkDate,
  }) async {
    if (currentEmployee == null) return;
    final settings =
        ref.read(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;
    final ok = await confirmWorkReportEdit(
      context,
      period: _period,
      periodKey: widget.periodKey,
      settings: settings,
    );
    if (!ok) return;
    try {
      await service.upsertJobLine(
        line: line,
        actor: currentEmployee!,
        isAdminEdit: _isAdminEdit,
        previousHours: prevHours,
        previousSummary: prevSummary,
        previousWorkDate: prevWorkDate,
        settings: settings,
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
                            onSave: (updated, prevH, prevS, prevD) =>
                                _saveLine(
                              service,
                              updated,
                              prevHours: prevH,
                              prevSummary: prevS,
                              prevWorkDate: prevD,
                            ),
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
    String? prevWorkDate,
  ) onSave;

  @override
  State<_JobLineTile> createState() => _JobLineTileState();
}

class _JobLineTileState extends State<_JobLineTile> {
  static final _dateFmt = DateFormat('d MMM yyyy');

  late final TextEditingController _hoursCtrl;
  late final TextEditingController _summaryCtrl;
  DateTime? _workDate;
  bool _expanded = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _hoursCtrl = TextEditingController(
      text: widget.line.hours == 0 ? '' : widget.line.hours.toString(),
    );
    _summaryCtrl = TextEditingController(text: widget.line.billingSummary);
    _workDate = widget.line.workDate;
    _hoursCtrl.addListener(_markDirty);
    _summaryCtrl.addListener(_markDirty);
  }

  void _markDirty() {
    final hours = double.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final dirty = hours != widget.line.hours ||
        _summaryCtrl.text.trim() != widget.line.billingSummary ||
        !_sameDate(_workDate, widget.line.workDate);
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  bool _sameDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void didUpdateWidget(covariant _JobLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.id != widget.line.id ||
        (!_dirty &&
            (oldWidget.line.hours != widget.line.hours ||
                oldWidget.line.billingSummary != widget.line.billingSummary ||
                !_sameDate(oldWidget.line.workDate, widget.line.workDate)))) {
      _hoursCtrl.text =
          widget.line.hours == 0 ? '' : widget.line.hours.toString();
      _summaryCtrl.text = widget.line.billingSummary;
      _workDate = widget.line.workDate;
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    if (!widget.editable) return;
    final initial = _workDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Timesheet work date',
    );
    if (picked == null) return;
    setState(() {
      _workDate = WorkReportJobLine.dateOnly(picked);
    });
    _markDirty();
  }

  void _commit() {
    final hours = double.tryParse(_hoursCtrl.text.trim()) ?? 0;
    if (_workDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a work date for this job line'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
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
      workDate: _workDate,
      createdAt: widget.line.createdAt,
      updatedAt: widget.line.updatedAt,
    );
    final prevDate = widget.line.workDate != null
        ? WorkReportJobLine.dateOnly(widget.line.workDate!).toIso8601String()
        : '';
    widget.onSave(
      updated,
      widget.line.hours.toString(),
      widget.line.billingSummary,
      prevDate,
    );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final scheme = Theme.of(context).colorScheme;
    final orphanBg = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final dateLabel =
        _workDate != null ? _dateFmt.format(_workDate!) : 'Tap to set date';

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
            if (_workDate != null) _dateFmt.format(_workDate!),
            line.jobMeta.locationLabel,
            if (_dirty) '• Unsaved',
          ].where((s) => s.trim().isNotEmpty).join(' · '),
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
                OutlinedButton.icon(
                  onPressed: widget.editable ? _pickDate : null,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(dateLabel),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Timesheet date only — does not change the job card.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                ),
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
