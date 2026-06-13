import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../providers/ink_provider.dart';

/// IBC register — shows all IBCs with a status filter (All / Received /
/// Transferred). Dense list with colour name, kg, status chip, dates, and
/// wash toloul for transferred IBCs.
class InkIbcRegisterScreen extends ConsumerStatefulWidget {
  const InkIbcRegisterScreen({super.key});

  @override
  ConsumerState<InkIbcRegisterScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcRegisterScreen> {
  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('d MMM yyyy');

  /// null = All
  InkIbcStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ibcsAsync = ref.watch(inkAllIbcsProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final nameByCode = {for (final i in items) i.itemCode: i.displayName};

    return Scaffold(
      appBar: AppBar(title: const Text('IBC Register')),
      body: Column(
        children: [
          // ── Filter bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  _filterChip(context, null, 'All'),
                  _filterChip(context, InkIbcStatus.received, 'Received'),
                  _filterChip(context, InkIbcStatus.transferred, 'Transferred'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // ── List ────────────────────────────────────────────────────────
          Expanded(
            child: ibcsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final ibcs = _filter == null
                    ? all
                    : all.where((b) => b.status == _filter).toList();

                if (ibcs.isEmpty) {
                  final label = switch (_filter) {
                    null => 'No IBCs recorded yet.',
                    InkIbcStatus.received =>
                      'No IBCs currently in received state.',
                    InkIbcStatus.transferred =>
                      'No transferred IBCs found.',
                  };
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(label,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant)),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: ibcs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final ibc = ibcs[i];
                    final colour =
                        nameByCode[ibc.itemCode] ?? ibc.itemCode;
                    final isTransferred =
                        ibc.status == InkIbcStatus.transferred;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status icon column
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 2, right: 12),
                            child: Icon(
                              isTransferred
                                  ? Icons.check_circle_outline
                                  : Icons.propane_tank_outlined,
                              size: 22,
                              color: isTransferred
                                  ? scheme.tertiary
                                  : scheme.primary,
                            ),
                          ),
                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // IBC number + status chip
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ibc.ibcNumber,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight:
                                                    FontWeight.w600),
                                      ),
                                    ),
                                    _StatusChip(
                                        status: ibc.status,
                                        scheme: scheme),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // Colour + kg
                                Text(
                                  '$colour · ${_qty.format(ibc.kg)} kg',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                                const SizedBox(height: 2),
                                // Received date (+ supplier)
                                Text(
                                  'Received ${_df.format(ibc.receivedDate)}'
                                  '${ibc.supplierName != null ? ' · ${ibc.supplierName}' : ''}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color:
                                              scheme.onSurfaceVariant),
                                ),
                                // Transferred date + wash toloul (when applicable)
                                if (isTransferred) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Transferred ${ibc.transferredDate != null ? _df.format(ibc.transferredDate!) : '—'}'
                                    '${ibc.washTolulLitres != null ? ' · Wash ${_qty.format(ibc.washTolulLitres!)} LTS' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: scheme.tertiary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
      BuildContext context, InkIbcStatus? value, String label) {
    final selected = _filter == value;
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
        fontWeight:
            selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.scheme});
  final InkIbcStatus status;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final isTransferred = status == InkIbcStatus.transferred;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isTransferred
            ? scheme.tertiaryContainer
            : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isTransferred ? 'Transferred' : 'Received',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isTransferred
                  ? scheme.onTertiaryContainer
                  : scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
