import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/work_report_job_line.dart';
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import '../services/firestore_service.dart';
import '../services/work_report_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart';
import '../utils/work_report_csv.dart';
import '../utils/work_report_daily_hours.dart';
import '../utils/work_report_pdf.dart';
import '../utils/work_report_period_utils.dart';
import '../utils/work_report_soft_lock.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import 'work_report_job_lines_screen.dart';
import 'work_report_preview_screen.dart';

class WorkReportHubScreen extends ConsumerStatefulWidget {
  const WorkReportHubScreen({super.key, this.initialSubjectClockNo});

  final String? initialSubjectClockNo;

  @override
  ConsumerState<WorkReportHubScreen> createState() =>
      _WorkReportHubScreenState();
}

class _WorkReportHubScreenState extends ConsumerState<WorkReportHubScreen> {
  bool _generatingPdf = false;
  bool _exportingCsv = false;
  bool _refreshingJobs = false;
  bool _autoRefreshTried = false;
  bool _savingNotes = false;
  final _notesCtrl = TextEditingController();
  String _notesLoadedFor = '';
  String _notesBaseline = '';

  String get _actorClockNo => currentEmployee?.clockNo ?? '';

  String get _subjectClockNo {
    final override = ref.watch(workReportSubjectClockProvider);
    if (override != null && override.isNotEmpty) return override;
    if (widget.initialSubjectClockNo != null) return widget.initialSubjectClockNo!;
    return _actorClockNo;
  }

  bool get _isAdminView =>
      isAdmin(currentEmployee) && _subjectClockNo != _actorClockNo;

  @override
  void initState() {
    super.initState();
    if (widget.initialSubjectClockNo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(workReportSubjectClockProvider.notifier).state =
            widget.initialSubjectClockNo;
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncNotesFromPeriod(WorkReportPeriod? period, String periodKey) {
    final key = '${_subjectClockNo}_$periodKey';
    final text = period?.notes ?? '';
    final dirty = _notesCtrl.text.trim() != _notesBaseline.trim();
    if (_notesLoadedFor == key) {
      // Period doc arrived after first paint — adopt server notes if user idle.
      if (!dirty && text != _notesBaseline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _notesBaseline = text;
            _notesCtrl.text = text;
          });
        });
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _notesLoadedFor = key;
        _notesBaseline = text;
        _notesCtrl.text = text;
      });
    });
  }

  Future<void> _saveNotes(WorkReportService service) async {
    if (currentEmployee == null) return;
    final settings =
        ref.read(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;
    final periodKey = ref.read(workReportPeriodKeyProvider);
    final period = await service
        .watchPeriod(_subjectClockNo, periodKey)
        .first
        .timeout(const Duration(seconds: 8));
    if (!mounted) return;
    final ok = await confirmWorkReportEdit(
      context,
      period: period,
      periodKey: periodKey,
      settings: settings,
    );
    if (!ok || !mounted) return;
    setState(() => _savingNotes = true);
    try {
      if (period == null) {
        final subject = await FirestoreService().getEmployee(_subjectClockNo);
        if (subject != null) {
          await service.ensurePeriodHeader(
            clockNo: _subjectClockNo,
            periodKey: periodKey,
            subject: subject,
            actor: currentEmployee!,
            settings: settings,
          );
        }
      }
      await service.updatePeriodNotes(
        clockNo: _subjectClockNo,
        periodKey: periodKey,
        notes: _notesCtrl.text,
        actor: currentEmployee!,
        settings: settings,
      );
      _notesBaseline = _notesCtrl.text.trim();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notes save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  Future<void> _maybeAutoRefresh(
    WorkReportService service,
    WorkReportSettings settings,
    WorkReportPeriod? period,
  ) async {
    if (_autoRefreshTried || currentEmployee == null) return;
    if (!WorkReportPeriodUtils.isPeriodEditable(
      ref.read(workReportPeriodKeyProvider),
      editablePeriodsBack: settings.editablePeriodsBack,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    )) {
      return;
    }
    final needs = period == null || period.jobLinesRefreshedAt == null;
    _autoRefreshTried = true;
    if (!needs) return;
    await _refreshJobList(service);
  }

  Future<
      ({
        WorkReportPeriod period,
        List<WorkReportJobLine> jobLines,
      })?> _loadExportData(WorkReportService service) async {
    final periodKey = ref.read(workReportPeriodKeyProvider);
    final clockNo = _subjectClockNo;
    final settings =
        ref.read(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;

    final period = await service
        .watchPeriod(clockNo, periodKey)
        .first
        .timeout(const Duration(seconds: 10));
    final jobLines = await service
        .watchJobLines(clockNo, periodKey)
        .first
        .timeout(const Duration(seconds: 10));

    service.validateDailyHoursCap(
      jobLines: jobLines,
      settings: settings,
    );

    final subjectEmp = await FirestoreService().getEmployee(clockNo);
    if (subjectEmp != null && currentEmployee != null) {
      await service.ensurePeriodHeader(
        clockNo: clockNo,
        periodKey: periodKey,
        subject: subjectEmp,
        actor: currentEmployee!,
      );
    }

    final periodForExport = period ??
        await service
            .watchPeriod(clockNo, periodKey)
            .first
            .timeout(const Duration(seconds: 10));

    if (periodForExport == null) {
      throw WorkReportValidationException(
        'Add job card lines before exporting',
      );
    }

    if (jobLines.isEmpty) {
      throw WorkReportValidationException(
        'Add job card lines before exporting',
      );
    }

    return (
      period: periodForExport,
      jobLines: jobLines,
    );
  }

  Future<void> _generatePdf(WorkReportService service) async {
    setState(() => _generatingPdf = true);
    try {
      final data = await _loadExportData(service);
      if (data == null) return;
      final settings =
          ref.read(workReportSettingsProvider).valueOrNull ??
              WorkReportSettings.defaults;

      var postPdfEdits = 0;
      if (data.period.hasPdf &&
          settings.includePostPdfEditNote &&
          data.period.pdfGeneratedAt != null) {
        postPdfEdits = await service.countEditsAfterPdf(
          clockNo: data.period.clockNo,
          periodKey: data.period.periodKey,
          pdfGeneratedAt: data.period.pdfGeneratedAt!,
        );
      }

      final bytes = await WorkReportPdfExporter.buildPdfBytes(
        period: data.period,
        jobLines: data.jobLines,
        settings: settings,
        postPdfEditCount: postPdfEdits,
      );

      if (!mounted) return;
      final shared = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => WorkReportPreviewScreen(
            period: data.period,
            pdfBytes: bytes,
            onShare: () async {
              final file = await WorkReportPdfExporter.writePdfFile(
                bytes: bytes,
                period: data.period,
              );
              await WorkReportPdfExporter.sharePdfFile(
                file: file,
                period: data.period,
              );
              if (currentEmployee != null) {
                await service.recordPdfGenerated(
                  clockNo: data.period.clockNo,
                  periodKey: data.period.periodKey,
                  actor: currentEmployee!,
                );
              }
            },
          ),
        ),
      );

      if (shared == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF shared')),
        );
      }
    } on WorkReportValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportCsv(WorkReportService service) async {
    setState(() => _exportingCsv = true);
    try {
      final data = await _loadExportData(service);
      if (data == null) return;
      final settings =
          ref.read(workReportSettingsProvider).valueOrNull ??
              WorkReportSettings.defaults;
      await WorkReportCsvExporter.generateAndShare(
        period: data.period,
        jobLines: data.jobLines,
        settings: settings,
      );
    } on WorkReportValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _refreshJobList(WorkReportService service) async {
    if (currentEmployee == null) return;
    setState(() => _refreshingJobs = true);
    try {
      final subject = await FirestoreService().getEmployee(_subjectClockNo);
      if (subject == null) {
        throw WorkReportValidationException('Worker not found');
      }
      final settings =
          ref.read(workReportSettingsProvider).valueOrNull ??
              WorkReportSettings.defaults;
      final added = await service.refreshJobLines(
        clockNo: _subjectClockNo,
        periodKey: ref.read(workReportPeriodKeyProvider),
        settings: settings,
        subject: subject,
        actor: currentEmployee!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added job card(s)')),
        );
      }
    } on WorkReportValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingJobs = false);
    }
  }

  void _shiftPeriod(int direction, WorkReportSettings settings) {
    final key = ref.read(workReportPeriodKeyProvider);
    final next = direction < 0
        ? WorkReportPeriodUtils.previousPeriodKey(
            key,
            editablePeriodsBack: settings.editablePeriodsBack,
            periodMode: settings.defaultPeriodMode,
            periodStartDay: settings.periodStartDay,
          )
        : WorkReportPeriodUtils.nextPeriodKey(
            key,
            editablePeriodsBack: settings.editablePeriodsBack,
            periodMode: settings.defaultPeriodMode,
            periodStartDay: settings.periodStartDay,
          );
    if (next == null) return;
    _autoRefreshTried = false;
    ref.read(workReportPeriodKeyProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(workReportSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? WorkReportSettings.defaults;
    final periodKey = ref.watch(workReportPeriodKeyProvider);
    final selectable = WorkReportPeriodUtils.selectablePeriodKeys(
      editablePeriodsBack: settings.editablePeriodsBack,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    if (!selectable.contains(periodKey) && selectable.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(workReportPeriodKeyProvider.notifier).state = selectable.first;
      });
    }
    final service = ref.watch(workReportServiceProvider);
    final periodStream = service.watchPeriod(_subjectClockNo, periodKey);
    final jobLinesStream = service.watchJobLines(_subjectClockNo, periodKey);
    final editable = WorkReportPeriodUtils.isPeriodEditable(
      periodKey,
      editablePeriodsBack: settings.editablePeriodsBack,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    final isPast = WorkReportPeriodUtils.isPastPeriod(
      periodKey,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    final isCurrent = WorkReportPeriodUtils.isCurrentPeriod(
      periodKey,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    final canGoBack = WorkReportPeriodUtils.previousPeriodKey(
          periodKey,
          editablePeriodsBack: settings.editablePeriodsBack,
          periodMode: settings.defaultPeriodMode,
          periodStartDay: settings.periodStartDay,
        ) !=
        null;
    final canGoForward = WorkReportPeriodUtils.nextPeriodKey(
          periodKey,
          editablePeriodsBack: settings.editablePeriodsBack,
          periodMode: settings.defaultPeriodMode,
          periodStartDay: settings.periodStartDay,
        ) !=
        null;

    if (!canUseWorkReportModule(currentEmployee, settings)) {
      return Scaffold(
        appBar: const CtpAppBar(title: 'My Timesheet'),
        body: const Center(child: Text('My Timesheet is not enabled for you.')),
      );
    }

    return Scaffold(
      appBar: CtpAppBar(
        title: _isAdminView ? 'Timesheet (admin)' : 'My Timesheet',
        actions: [
          if (_exportingCsv)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Export CSV',
              onPressed: () => _exportCsv(service),
              icon: const Icon(Icons.table_chart_outlined),
            ),
          if (_generatingPdf)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Preview & share PDF',
              onPressed: () => _generatePdf(service),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: StreamBuilder(
        stream: periodStream,
        builder: (context, snapshot) {
          final period = snapshot.data;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _maybeAutoRefresh(service, settings, period);
          });
          return StreamBuilder(
            stream: jobLinesStream,
            builder: (context, jobSnap) {
              final jobLines = jobSnap.data ?? const [];
              final daily = WorkReportDailyHours.fromJobLines(jobLines)
                  .where((d) => d.hours > 0.001)
                  .toList();
              final hoursFmt = NumberFormat('#,##0.#');
              final totalHours = period?.totalHours ??
                  jobLines.fold<double>(0, (s, l) => s + l.hours);
              final softWarn = service.monthlyHoursSoftWarning(
                totalHours: totalHours,
                periodKey: periodKey,
                settings: settings,
              );
              _syncNotesFromPeriod(period, periodKey);
              final notesDirty =
                  _notesCtrl.text.trim() != _notesBaseline.trim();

              return ListView(
                padding: ScreenInsets.symmetricScroll(
                  context,
                  horizontal: 16,
                  vertical: 16,
                ),
                children: [
                  if (_isAdminView)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.admin_panel_settings),
                        title: Text('Viewing clock #$_subjectClockNo'),
                        subtitle: Text(period?.employeeName ?? ''),
                      ),
                    ),
                  if (isAdmin(currentEmployee))
                    _AdminWorkerPicker(settings: settings),
                  const SizedBox(height: 8),

                  // Week navigator
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous week',
                            onPressed: canGoBack
                                ? () => _shiftPeriod(-1, settings)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  WorkReportPeriodUtils.periodShortLabel(
                                    periodKey,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  WorkReportPeriodUtils.periodLabel(periodKey),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).appColors.textMuted,
                                  ),
                                ),
                                if (isCurrent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Current week',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .appColors
                                            .wasteGreen,
                                      ),
                                    ),
                                  )
                                else if (isPast)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Past week — edits are audited',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next week',
                            onPressed: canGoForward
                                ? () => _shiftPeriod(1, settings)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (isPast) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.35),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.history, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You are viewing a past week. Changes require confirmation '
                                'and are written to the audit trail.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (period?.hasPdf == true) ...[
                    const SizedBox(height: 12),
                    _PdfWarningBanner(period: period!),
                  ],
                  if (softWarn != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.35),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          softWarn,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SummaryCard(
                    label: 'Total hours',
                    value: totalHours,
                    color: Theme.of(context).appColors.wasteGreen,
                    bold: true,
                  ),
                  if (daily.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Hours by day',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      'Based on each job line’s timesheet work date.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).appColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in daily)
                          _DailyHoursChip(
                            label: d.chipLabel(hoursFmt.format(d.hours)),
                            overCap:
                                d.hours > settings.maxHoursPerDay + 0.001,
                            maxHours: settings.maxHoursPerDay,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: !editable || _refreshingJobs
                        ? null
                        : () => _refreshJobList(service),
                    icon: _refreshingJobs
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _refreshingJobs
                          ? 'Refreshing job cards…'
                          : 'Refresh job cards',
                    ),
                  ),
                  if (period?.jobLinesRefreshedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Last refreshed ${DateFormat('d MMM yyyy HH:mm').format(period!.jobLinesRefreshedAt!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).appColors.textMuted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkReportJobLinesScreen(
                          subjectClockNo: _subjectClockNo,
                          periodKey: periodKey,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.assignment),
                    label: Text(
                      jobLines.isEmpty
                          ? 'Job cards for week'
                          : 'Job cards (${jobLines.length})',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Notes (optional)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Shown at the bottom of the PDF for Accounts / manager.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    enabled: editable && !_savingNotes,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'e.g. Standby Thursday, call-out hours…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: !editable || _savingNotes || !notesDirty
                          ? null
                          : () => _saveNotes(service),
                      child: Text(
                        _savingNotes
                            ? 'Saving…'
                            : (notesDirty ? 'Save notes' : 'Notes saved'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use the PDF / CSV icons in the top bar to export this week.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).appColors.textMuted,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DailyHoursChip extends StatelessWidget {
  const _DailyHoursChip({
    required this.label,
    required this.overCap,
    required this.maxHours,
  });

  final String label;
  final bool overCap;
  final double maxHours;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: overCap ? 'Exceeds ${maxHours}h daily limit' : label,
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        backgroundColor: overCap
            ? scheme.errorContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerHighest,
        side: BorderSide(
          color: overCap ? scheme.error : scheme.outline.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)} h',
              style: TextStyle(
                fontSize: bold ? 18 : 16,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfWarningBanner extends StatelessWidget {
  const _PdfWarningBanner({required this.period});

  final WorkReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warning = Colors.amber.shade400;
    final generated = period.pdfGeneratedAt != null
        ? DateFormat('d MMM yyyy HH:mm').format(period.pdfGeneratedAt!)
        : '';

    return Card(
      color: Colors.amber.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PDF generated $generated (v${period.pdfVersion}). '
                'Editing may not match what Accounts received.',
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminWorkerPicker extends ConsumerStatefulWidget {
  const _AdminWorkerPicker({required this.settings});
  final WorkReportSettings settings;

  @override
  ConsumerState<_AdminWorkerPicker> createState() => _AdminWorkerPickerState();
}

class _AdminWorkerPickerState extends ConsumerState<_AdminWorkerPicker> {
  final Map<String, String> _namesByClock = {};
  bool _loadingNames = true;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  @override
  void didUpdateWidget(covariant _AdminWorkerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.enabledClockNos != widget.settings.enabledClockNos) {
      _loadNames();
    }
  }

  Future<void> _loadNames() async {
    setState(() => _loadingNames = true);
    final fs = FirestoreService();
    final next = <String, String>{};
    for (final clock in widget.settings.enabledClockNos) {
      final emp = await fs.getEmployee(clock);
      if (emp != null && emp.name.trim().isNotEmpty) {
        next[clock] = emp.name.trim();
      }
    }
    if (mounted) {
      setState(() {
        _namesByClock
          ..clear()
          ..addAll(next);
        _loadingNames = false;
      });
    }
  }

  String _label(String clock) {
    final name = _namesByClock[clock];
    if (name != null && name.isNotEmpty) return '$name (#$clock)';
    return 'Clock #$clock';
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(workReportSubjectClockProvider) ??
        currentEmployee?.clockNo ??
        '';
    final muted = Theme.of(context).appColors.textMuted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('View worker',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: widget.settings.enabledClockNos.contains(current)
                  ? current
                  : (widget.settings.enabledClockNos.isNotEmpty
                      ? widget.settings.enabledClockNos.first
                      : null),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in widget.settings.enabledClockNos)
                  DropdownMenuItem(value: c, child: Text(_label(c))),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(workReportSubjectClockProvider.notifier).state = v;
                }
              },
            ),
            if (_loadingNames)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Loading names…',
                    style: TextStyle(fontSize: 11, color: muted)),
              ),
          ],
        ),
      ),
    );
  }
}
