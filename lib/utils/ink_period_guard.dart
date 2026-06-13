import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_settings.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import 'role.dart' as role_utils;

/// Returns `true` if the caller may proceed with writing a transaction whose
/// effective date falls in [effectiveAt]'s period.
///
/// Behaviour:
/// - Period open → returns `true` immediately (no prompt).
/// - Period closed + manager → shows a warning dialog. On confirm, flags the
///   period for re-issue (`periods_needing_reissue`) and returns `true`.
///   On cancel → returns `false`.
/// - Period closed + non-manager → shows an info dialog and returns `false`.
Future<bool> confirmClosedPeriodOverride(
  BuildContext context,
  WidgetRef ref,
  DateTime effectiveAt,
) async {
  final settings = ref.read(inkSettingsProvider).valueOrNull;
  if (settings == null || !settings.isPeriodClosed(effectiveAt)) {
    return true;
  }

  final pk = InkSettings.periodKey(effectiveAt);
  final emp = ref.read(currentEmployeeProvider).valueOrNull;
  final isManager = role_utils.isInkManager(emp);

  if (!isManager) {
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Period finalised'),
        content: Text(
          'The period $pk has been closed and the report finalised. '
          'Only a manager can post into a closed period.',
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

  // Manager — ask for confirmation and flag for re-issue on confirm.
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Override closed period?'),
      content: Text(
        'The period $pk has been finalised.\n\n'
        'Posting into a closed period will mark this month\'s report '
        'for re-issue. Continue?',
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

  // Flag the period so the report screen shows a re-issue banner.
  await ref.read(inkServiceProvider).flagPeriodForReissue(pk);
  return true;
}
