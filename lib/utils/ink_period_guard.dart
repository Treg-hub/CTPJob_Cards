import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_settings.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import 'role.dart' as role_utils;

/// Returns `true` if the caller may proceed with writing a transaction whose
/// effective date is [effectiveAt].
///
/// Lock rule (Fix #3 — admin-only backdating): a date **on or before the latest
/// completed month-end count**, or in an explicitly closed period, is FINALISED.
/// Posting into it is **admin-only** — managers are blocked too; nothing changes
/// before a month-end count unless [role_utils.isAdmin]. This protects the count
/// snapshot baseline and bounds the recompute surface. On an admin override the
/// affected month is flagged for re-issue. Open dates proceed with no prompt.
Future<bool> confirmClosedPeriodOverride(
  BuildContext context,
  WidgetRef ref,
  DateTime effectiveAt,
) async {
  // Await loaded values so the lock is enforced even when these streams have not
  // been read yet on this screen (never silently skip the lock on a cold cache).
  final settings = await ref.read(inkSettingsProvider.future);
  final events = await ref.read(inkCountEventsProvider.future);
  if (!context.mounted) return false;

  DateTime? latestCount;
  for (final e in events) {
    if (latestCount == null || e.countDate.isAfter(latestCount)) {
      latestCount = e.countDate;
    }
  }
  final beforeLatestCount =
      latestCount != null && !effectiveAt.isAfter(latestCount);
  final periodClosed = settings.isPeriodClosed(effectiveAt);

  if (!beforeLatestCount && !periodClosed) {
    return true; // open period — proceed with no prompt
  }

  final pk = InkSettings.periodKey(effectiveAt);
  final isAdmin =
      role_utils.isAdmin(ref.read(currentEmployeeProvider).valueOrNull);

  if (!isAdmin) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Period finalised'),
        content: Text(
          beforeLatestCount
              ? 'This date is on or before the last month-end count, so '
                  'period $pk is finalised. Only an admin can post into it.'
              : 'The period $pk has been closed and the report finalised. '
                  'Only an admin can post into a closed period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  // Admin — confirm and flag the month for re-issue on confirm.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Override finalised period?'),
      content: Text(
        'Period $pk is finalised '
        '(${beforeLatestCount ? 'on/before the last month-end count' : 'closed'}).'
        '\n\nPosting here will mark that month\'s report for re-issue and '
        'recompute the affected count snapshot. Continue?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Override & post'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  await ref.read(inkServiceProvider).flagPeriodForReissue(pk);
  return true;
}
