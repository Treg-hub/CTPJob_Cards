import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/work_report_period.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import '../services/firestore_service.dart';
import '../services/work_report_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart';
import '../utils/work_report_pdf.dart';
import '../utils/work_report_period_utils.dart';
import '../widgets/ctp_app_bar.dart';
import 'work_report_additional_work_screen.dart';
import 'work_report_job_lines_screen.dart';

class WorkReportHubScreen extends ConsumerStatefulWidget {
  const WorkReportHubScreen({super.key, this.initialSubjectClockNo});

  final String? initialSubjectClockNo;

  @override
  ConsumerState<WorkReportHubScreen> createState() =>
      _WorkReportHubScreenState();
}

class _WorkReportHubScreenState extends ConsumerState<WorkReportHubScreen> {
  bool _generatingPdf = false;

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

  Future<void> _generatePdf(WorkReportService service) async {
    final periodKey = ref.read(workReportPeriodKeyProvider);
    final clockNo = _subjectClockNo;
    setState(() => _generatingPdf = true);
    try {
      final period = await service
          .watchPeriod(clockNo, periodKey)
          .first
          .timeout(const Duration(seconds: 10));
      final jobLines = await service
          .watchJobLines(clockNo, periodKey)
          .first
          .timeout(const Duration(seconds: 10));
      final additional = await service
          .watchAdditionalLines(clockNo, periodKey)
          .first
          .timeout(const Duration(seconds: 10));
      final settings =
          ref.read(workReportSettingsProvider).valueOrNull ??
              WorkReportSettings.defaults;

      service.validateDailyHoursCap(
        additionalLines: additional,
        settings: settings,
      );

      final subjectEmp =
          await FirestoreService().getEmployee(clockNo);
      if (subjectEmp != null && currentEmployee != null) {
        await service.ensurePeriodHeader(
          clockNo: clockNo,
          periodKey: periodKey,
          subject: subjectEmp,
          actor: currentEmployee!,
        );
      }

      final periodForPdf = period ??
          await service
              .watchPeriod(clockNo, periodKey)
              .first
              .timeout(const Duration(seconds: 10));

      if (periodForPdf == null) {
        throw WorkReportValidationException(
          'Add job card or additional work lines before generating PDF',
        );
      }

      await WorkReportPdfExporter.generateAndShare(
        period: periodForPdf,
        jobLines: jobLines,
        additionalLines: additional,
      );

      if (currentEmployee != null) {
        await service.recordPdfGenerated(
          clockNo: clockNo,
          periodKey: periodKey,
          actor: currentEmployee!,
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

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(workReportSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? WorkReportSettings.defaults;
    final periodKey = ref.watch(workReportPeriodKeyProvider);
    final selectable = WorkReportPeriodUtils.selectablePeriodKeys(
      editablePeriodsBack: settings.editablePeriodsBack,
    );
    final service = ref.watch(workReportServiceProvider);
    final periodStream = service.watchPeriod(_subjectClockNo, periodKey);

    if (!canUseWorkReportModule(currentEmployee, settings)) {
      return Scaffold(
        appBar: const CtpAppBar(title: 'My Timesheet'),
        body: const Center(child: Text('My Timesheet is not enabled for you.')),
      );
    }

    return Scaffold(
      appBar: CtpAppBar(
        title: _isAdminView ? 'Timesheet (admin)' : 'My Timesheet',
      ),
      body: StreamBuilder(
        stream: periodStream,
        builder: (context, snapshot) {
          final period = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
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
              Text('Period', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final key in selectable)
                    ChoiceChip(
                      label: Text(WorkReportPeriodUtils.periodLabel(key)),
                      selected: periodKey == key,
                      onSelected: (_) {
                        ref.read(workReportPeriodKeyProvider.notifier).state =
                            key;
                      },
                    ),
                ],
              ),
              if (period?.hasPdf == true) ...[
                const SizedBox(height: 12),
                _PdfWarningBanner(period: period!),
              ],
              const SizedBox(height: 16),
              _SummaryCard(
                label: 'Job card hours',
                value: period?.totalJobHours ?? 0,
                color: kBrandOrange,
              ),
              const SizedBox(height: 8),
              _SummaryCard(
                label: 'Additional hours',
                value: period?.totalAdditionalHours ?? 0,
                color: Theme.of(context).appColors.statusOpen,
              ),
              const SizedBox(height: 8),
              _SummaryCard(
                label: 'Total hours',
                value: period?.totalHours ?? 0,
                color: Theme.of(context).appColors.wasteGreen,
                bold: true,
              ),
              const SizedBox(height: 24),
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
                label: const Text('Job cards for period'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorkReportAdditionalWorkScreen(
                      subjectClockNo: _subjectClockNo,
                      periodKey: periodKey,
                    ),
                  ),
                ),
                icon: const Icon(Icons.note_add),
                label: const Text('Additional work'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed:
                    _generatingPdf ? null : () => _generatePdf(service),
                icon: _generatingPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_generatingPdf ? 'Generating…' : 'Generate PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).appColors.wasteGreen,
                  foregroundColor: onColor(
                    Theme.of(context).appColors.wasteGreen,
                  ),
                ),
              ),
            ],
          );
        },
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
                child: Text('Loading names…', style: TextStyle(fontSize: 11, color: muted)),
              ),
          ],
        ),
      ),
    );
  }
}