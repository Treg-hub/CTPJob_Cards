import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../providers/ink_provider.dart';
import '../providers/lurgi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/presence_gating.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';

/// Read-only list of Ink Factory toloul recovery posts for Lurgi operators.
/// Scoped to the **open ink count period** (`latest_active_count_date`).
/// Capture remains on Ink Factory Toloul Recovery — no writes from this screen.
class LurgiInkFactoryRecoveryScreen extends ConsumerWidget {
  const LurgiInkFactoryRecoveryScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM yyyy HH:mm');
  static final _day = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Ink Factory Recovery');
    }
    if (!role_utils.isLurgiUser(currentEmployee)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ink Factory Recovery')),
        body: const Center(child: Text('Lurgi department only.')),
      );
    }

    final async = ref.watch(lurgiInkFactoryRecoveriesProvider);
    final settings = ref.watch(inkSettingsProvider).valueOrNull;
    final periodFrom = settings?.latestActiveCountDate;
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Ink Factory Recovery')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load recoveries: $e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(lurgiInkFactoryRecoveriesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(lurgiInkFactoryRecoveriesProvider);
              ref.invalidate(inkSettingsProvider);
              await ref.read(lurgiInkFactoryRecoveriesProvider.future);
            },
            child: ListView(
              padding: ScreenInsets.symmetricScroll(context),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'View only. Ink Factory records solvent recovered '
                          'into the factory tank. You cannot edit these entries.',
                          style: TextStyle(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          periodFrom == null
                              ? 'Period: all recorded recoveries (no month-end count yet).'
                              : 'Open count period: since ${_day.format(periodFrom)}.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: appColors.lurgiDark,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No recovery entries in this count period.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  for (final t in rows)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.recycling_outlined,
                          color: appColors.lurgiAccent,
                        ),
                        title: Text(
                          '${_qty.format(t.quantityDelta)} ${t.stockItemCode}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          [
                            _df.format(t.effectiveAt),
                            if (t.lurgiSource != null &&
                                t.lurgiSource!.trim().isNotEmpty)
                              t.lurgiSource!.trim(),
                            if (t.actorName.isNotEmpty) t.actorName,
                            if (t.seqNumber != null) t.seqNumber!,
                          ].join(' · '),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
