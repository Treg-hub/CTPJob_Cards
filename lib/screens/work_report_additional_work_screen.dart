import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../main.dart' show currentEmployee;
import '../models/work_report_additional_line.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../services/work_report_service.dart';
import '../utils/role.dart';
import '../utils/work_report_period_utils.dart';
import '../utils/work_report_soft_lock.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/work_report_job_link_picker.dart';

class WorkReportAdditionalWorkScreen extends ConsumerWidget {
  const WorkReportAdditionalWorkScreen({
    super.key,
    required this.subjectClockNo,
    required this.periodKey,
  });

  final String subjectClockNo;
  final String periodKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(workReportServiceProvider);

    final settings =
        ref.watch(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;
    final editable = WorkReportPeriodUtils.isPeriodEditable(
      periodKey,
      editablePeriodsBack: settings.editablePeriodsBack,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    final isAdminEdit =
        isAdmin(currentEmployee) && currentEmployee?.clockNo != subjectClockNo;

    final jobLinesStream = service.watchJobLines(subjectClockNo, periodKey);

    return Scaffold(
      appBar: CtpAppBar(
        title:
            'Additional work — ${WorkReportPeriodUtils.periodLabel(periodKey)}',
      ),
      floatingActionButton: editable
          ? FloatingActionButton(
              onPressed: () => _openEditor(
                context,
                ref,
                subjectClockNo: subjectClockNo,
                periodKey: periodKey,
                existing: null,
                editable: editable,
                isAdminEdit: isAdminEdit,
              ),
              child: const Icon(Icons.add),
            )
          : null,
      body: StreamBuilder(
        stream: FirestoreService().getMyJobCards(subjectClockNo),
        builder: (context, myWorkSnap) {
          return StreamBuilder(
            stream: jobLinesStream,
            builder: (context, jobSnap) {
              final linkOptions = WorkReportJobLinkOption.mergeSources(
                myWorkCards: myWorkSnap.data ?? const [],
                periodLines: jobSnap.data ?? const [],
              );

              return StreamBuilder(
            stream: service.watchAdditionalLines(subjectClockNo, periodKey),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final lines = snapshot.data!;
              if (lines.isEmpty) {
                return const Center(
                  child: Text(
                    'No additional work logged.\nTap + to add tasks not tied to a job card.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                padding: ScreenInsets.listPadding(
                  context,
                  horizontal: 12,
                  top: 12,
                  clearFab: editable,
                ),
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final line = lines[index];
                  final linkLabel = WorkReportJobLinkOption.labelForNumber(
                    line.linkedJobCardNumber,
                    linkOptions,
                  );
                  return Card(
                    child: ListTile(
                      title: Text(line.description,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${DateFormat('d MMM yyyy').format(line.workDate)} · '
                        '${line.hours.toStringAsFixed(1)} h'
                        '${linkLabel != null ? ' · $linkLabel' : ''}',
                      ),
                      trailing: editable
                          ? PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  _openEditor(
                                    context,
                                    ref,
                                    subjectClockNo: subjectClockNo,
                                    periodKey: periodKey,
                                    existing: line,
                                    editable: editable,
                                    isAdminEdit: isAdminEdit,
                                  );
                                } else if (action == 'delete') {
                                  final period = await service
                                      .watchPeriod(subjectClockNo, periodKey)
                                      .first
                                      .timeout(const Duration(seconds: 8));
                                  if (!context.mounted) return;
                                  final lockOk =
                                      await confirmWorkReportEditAfterPdf(
                                    context,
                                    period: period,
                                  );
                                  if (!lockOk || !context.mounted) return;
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete entry?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true && currentEmployee != null) {
                                    await service.deleteAdditionalLine(
                                      line: line,
                                      actor: currentEmployee!,
                                    );
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('Edit')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Delete')),
                              ],
                            )
                          : null,
                      onTap: editable
                          ? () => _openEditor(
                                context,
                                ref,
                                subjectClockNo: subjectClockNo,
                                periodKey: periodKey,
                                existing: line,
                                editable: editable,
                                isAdminEdit: isAdminEdit,
                              )
                          : null,
                    ),
                  );
                },
              );
              },
            );
          },
        );
        },
      ),
    );
  }

  static Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    required String subjectClockNo,
    required String periodKey,
    required WorkReportAdditionalLine? existing,
    required bool editable,
    required bool isAdminEdit,
  }) async {
    if (!editable || currentEmployee == null) return;
    final settings =
        ref.read(workReportSettingsProvider).valueOrNull ??
            WorkReportSettings.defaults;
    final service = ref.read(workReportServiceProvider);

    final period = await service
        .watchPeriod(subjectClockNo, periodKey)
        .first
        .timeout(const Duration(seconds: 10));
    if (!context.mounted) return;
    final ok = await confirmWorkReportEditAfterPdf(context, period: period);
    if (!ok || !context.mounted) return;

    final periodStart = WorkReportPeriodUtils.periodStart(
      periodKey,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );
    final periodEnd = WorkReportPeriodUtils.periodEnd(
      periodKey,
      periodMode: settings.defaultPeriodMode,
      periodStartDay: settings.periodStartDay,
    );

    List<WorkReportJobLinkOption> linkOptions = [];
    try {
      final myWork = await FirestoreService()
          .getMyJobCards(subjectClockNo)
          .first
          .timeout(const Duration(seconds: 12));
      final periodLines = await service
          .watchJobLines(subjectClockNo, periodKey)
          .first
          .timeout(const Duration(seconds: 12));
      linkOptions = WorkReportJobLinkOption.mergeSources(
        myWorkCards: myWork,
        periodLines: periodLines,
      );
    } catch (_) {
      // Picker still opens with period lines only if My Work fetch fails.
      final periodLines = await service
          .watchJobLines(subjectClockNo, periodKey)
          .first
          .timeout(const Duration(seconds: 12));
      linkOptions = WorkReportJobLinkOption.mergeSources(
        myWorkCards: const [],
        periodLines: periodLines,
      );
    }

    var workDate = existing?.workDate ?? DateTime.now();
    if (workDate.isBefore(periodStart)) workDate = periodStart;
    if (workDate.isAfter(periodEnd)) workDate = periodEnd;

    final hoursCtrl = TextEditingController(
      text: existing?.hours.toString() ?? '',
    );
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    int? linkedJob = existing?.linkedJobCardNumber;

    if (!context.mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final scheme = Theme.of(ctx).colorScheme;
            final muted = Theme.of(ctx).appColors.textMuted;
            final linkLabel = WorkReportJobLinkOption.labelForNumber(
              linkedJob,
              linkOptions,
            );

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom +
                    ScreenInsets.bottomSafe(ctx) +
                    16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'Add additional work' : 'Edit entry',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Work date'),
                    subtitle: Text(
                      DateFormat('d MMM yyyy').format(workDate),
                      style: TextStyle(color: scheme.onSurface),
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: workDate,
                        firstDate: periodStart,
                        lastDate: periodEnd,
                      );
                      if (picked != null) {
                        setSheetState(() => workDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hoursCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Hours (max ${settings.maxHoursPerDay}/day)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Link to job card (optional)',
                      style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showWorkReportJobLinkPicker(
                        ctx,
                        options: linkOptions,
                        selected: linkedJob,
                      );
                      if (picked?.changed == true) {
                        setSheetState(() => linkedJob = picked!.jobNumber);
                      }
                    },
                    icon: const Icon(Icons.link),
                    label: Text(
                      linkLabel ?? 'Choose from My Work',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;

    try {
      final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
      final line = WorkReportAdditionalLine(
        id: existing?.id ?? const Uuid().v4(),
        clockNo: existing?.clockNo ?? subjectClockNo,
        periodKey: periodKey,
        workDate: workDate,
        hours: hours,
        description: descCtrl.text.trim(),
        linkedJobCardNumber: linkedJob,
        createdByClockNo: currentEmployee!.clockNo,
      );

      final allLines = await service
          .watchAdditionalLines(line.clockNo, line.periodKey)
          .first;
      final merged = [
        for (final l in allLines)
          if (l.id != line.id) l,
        line,
      ];
      service.validateDailyHoursCap(
        additionalLines: merged,
        settings: settings,
      );

      await service.upsertAdditionalLine(
        line: line,
        actor: currentEmployee!,
        settings: settings,
        isCreate: existing == null,
        isAdminEdit: isAdminEdit,
        previous: existing,
      );
    } on WorkReportValidationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}