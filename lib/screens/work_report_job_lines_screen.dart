import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../models/employee.dart';
import '../models/work_report_job_line.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import '../services/firestore_service.dart';
import '../services/work_report_service.dart';
import '../utils/role.dart';
import '../utils/work_report_period_utils.dart';
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

  bool get _editable {
    final settings =
        ref.read(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;
    return WorkReportPeriodUtils.isPeriodEditable(
      widget.periodKey,
      editablePeriodsBack: settings.editablePeriodsBack,
    );
  }

  bool get _isAdminEdit =>
      isAdmin(currentEmployee) &&
      currentEmployee?.clockNo != widget.subjectClockNo;

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
    try {
      await service.upsertJobLine(
        line: line,
        actor: currentEmployee!,
        isAdminEdit: _isAdminEdit,
        previousHours: prevHours,
        previousSummary: prevSummary,
      );
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
                        padding: const EdgeInsets.symmetric(horizontal: 12),
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

  @override
  void initState() {
    super.initState();
    _hoursCtrl = TextEditingController(
      text: widget.line.hours == 0 ? '' : widget.line.hours.toString(),
    );
    _summaryCtrl = TextEditingController(text: widget.line.billingSummary);
  }

  @override
  void didUpdateWidget(covariant _JobLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.id != widget.line.id) {
      _hoursCtrl.text =
          widget.line.hours == 0 ? '' : widget.line.hours.toString();
      _summaryCtrl.text = widget.line.billingSummary;
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
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return Card(
      color: line.orphan ? Colors.grey.shade100 : null,
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
          line.jobMeta.locationLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (line.orphan)
                  const Text(
                    'No longer matches inclusion rules (hours kept).',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
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
                    child: TextButton(onPressed: _commit, child: const Text('Save')),
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