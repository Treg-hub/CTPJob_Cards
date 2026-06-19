import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../services/ink_service.dart';
import '../utils/ink_period_guard.dart';
import '../utils/role.dart' as role_utils;

/// Recent ink meter-reading sessions (one row per daily submit). Managers tap a
/// session to void it — reverses that session's meter consumptions and removes
/// the day's toloul readings so it can be re-entered (e.g. a wrong date).
/// Voiding into a finalised period is admin-only (closed-period guard).
class InkMeterSessionsScreen extends ConsumerWidget {
  const InkMeterSessionsScreen({super.key});

  static final _df = DateFormat('EEE d MMM yyyy HH:mm');

  Future<void> _void(
      BuildContext context, WidgetRef ref, InkMeterSession s) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void meter session?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reverses ${s.itemCount} ink meter reading(s) from '
                '${_df.format(s.readingDate)} and removes that day\'s toloul '
                'readings so the session can be re-entered.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason *'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Void session')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a reason for the void.')));
      return;
    }
    final allowed =
        await confirmClosedPeriodOverride(context, ref, s.readingDate);
    if (!allowed || !context.mounted) return;
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).voidMeterSession(
            s.sessionId,
            s.readingDate,
            reason: reason,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Meter session voided.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(inkRecentMeterSessionsProvider);
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('Meter Sessions')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sessions) => sessions.isEmpty
            ? const Center(
                child: Text('No meter sessions in the last 90 days.'))
            : ListView.separated(
                itemCount: sessions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  return ListTile(
                    leading: Icon(s.allVoided
                        ? Icons.cancel_outlined
                        : Icons.speed_outlined),
                    title: Text(
                      _df.format(s.readingDate),
                      style: s.allVoided
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    subtitle: Text(
                      '${s.itemCount} reading(s)'
                      '${s.actorName.isNotEmpty ? ' · ${s.actorName}' : ''}'
                      '${s.allVoided ? ' · VOIDED' : ''}',
                    ),
                    onTap: (isManager && !s.allVoided)
                        ? () => _void(context, ref, s)
                        : null,
                  );
                },
              ),
      ),
    );
  }
}
