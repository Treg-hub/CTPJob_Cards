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
import '../widgets/lurgi_period_banner.dart';

/// Read-only list of Ink Factory toloul recovery posts for Lurgi operators.
/// Strictly scoped to the **open ink count period** (`latest_active_count_date`).
class LurgiInkFactoryRecoveryScreen extends ConsumerWidget {
  const LurgiInkFactoryRecoveryScreen({super.key});

  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM yyyy HH:mm');

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

    final settingsAsync = ref.watch(inkSettingsProvider);
    final periodFrom = settingsAsync.valueOrNull?.latestActiveCountDate;
    final async = ref.watch(lurgiInkFactoryRecoveriesProvider);
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Ink Factory Recovery')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(lurgiInkFactoryRecoveriesProvider);
          ref.invalidate(inkSettingsProvider);
          await ref.read(inkSettingsProvider.future);
          await ref.read(lurgiInkFactoryRecoveriesProvider.future);
        },
        child: ListView(
          padding: ScreenInsets.symmetricScroll(context),
          children: [
            LurgiPeriodBanner(
              periodFrom: periodFrom,
              settingsLoading: settingsAsync.isLoading,
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'View only. Ink Factory records solvent recovered into the '
                  'factory tank. Only recoveries after the latest month-end '
                  'count are listed (same open period as Ink Factory).',
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (settingsAsync.isLoading || async.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (settingsAsync.hasError)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load ink period settings: ${settingsAsync.error}',
                  textAlign: TextAlign.center,
                ),
              )
            else if (periodFrom == null)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No month-end count on file yet — recovery history is hidden until a count establishes the open period.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text('Could not load recoveries: $e',
                          textAlign: TextAlign.center),
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
                data: (rows) {
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No recovery entries in this open count period.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return Column(
                    children: [
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
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
