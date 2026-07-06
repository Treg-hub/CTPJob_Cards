import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../main.dart' show currentEmployee;
import '../models/work_report_additional_line.dart';
import '../models/work_report_settings.dart';
import '../providers/work_report_provider.dart';
import '../services/work_report_service.dart';
import '../utils/role.dart';
import '../utils/work_report_period_utils.dart';
import '../widgets/ctp_app_bar.dart';

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
    );
    final isAdminEdit =
        isAdmin(currentEmployee) && currentEmployee?.clockNo != subjectClockNo;

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
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              return Card(
                child: ListTile(
                  title: Text(line.description,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${DateFormat('d MMM yyyy').format(line.workDate)} · '
                    '${line.hours.toStringAsFixed(1)} h'
                    '${line.linkedJobCardNumber != null ? ' · Job #${line.linkedJobCardNumber}' : ''}',
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
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete entry?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
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
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
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
    final periodStart = WorkReportPeriodUtils.periodStart(periodKey);

    final dateCtrl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(
        existing?.workDate ?? DateTime.now(),
      ),
    );
    final hoursCtrl = TextEditingController(
      text: existing?.hours.toString() ?? '',
    );
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final jobCtrl = TextEditingController(
      text: existing?.linkedJobCardNumber?.toString() ?? '',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
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
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Date (yyyy-MM-dd)',
                  border: OutlineInputBorder(),
                ),
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
              TextField(
                controller: jobCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Linked job # (optional)',
                  border: OutlineInputBorder(),
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

    if (saved != true) return;

    try {
      final workDate = DateTime.tryParse(dateCtrl.text.trim()) ?? periodStart;
      final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
      final linked = int.tryParse(jobCtrl.text.trim());
      final line = WorkReportAdditionalLine(
        id: existing?.id ?? const Uuid().v4(),
        clockNo: existing?.clockNo ?? subjectClockNo,
        periodKey: periodKey,
        workDate: workDate,
        hours: hours,
        description: descCtrl.text.trim(),
        linkedJobCardNumber: linked,
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