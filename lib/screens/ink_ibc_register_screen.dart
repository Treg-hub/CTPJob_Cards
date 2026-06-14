import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../providers/ink_provider.dart';

const _kRegColours = ['yellow', 'red', 'blue', 'black'];
const _kRegColourLabels = ['Yellow', 'Red', 'Blue', 'Black'];

/// IBC register — colour tabs (Yellow | Red | Blue | Black), each with a
/// search field and a sortable list of IBCs.  Status filter bar above the tabs
/// applies across all colours (All / Received / Consumed).
class InkIbcRegisterScreen extends ConsumerStatefulWidget {
  const InkIbcRegisterScreen({super.key});

  @override
  ConsumerState<InkIbcRegisterScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcRegisterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// null = All
  InkIbcStatus? _filter;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _kRegColours.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ibcsAsync = ref.watch(inkAllIbcsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IBC Register'),
        bottom: TabBar(
          controller: _tab,
          tabs: [for (final l in _kRegColourLabels) Tab(text: l)],
        ),
      ),
      body: Column(
        children: [
          // ── Status filter ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  _filterChip(context, null, 'All'),
                  _filterChip(context, InkIbcStatus.received, 'Received'),
                  _filterChip(
                      context, InkIbcStatus.transferred, 'Consumed'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // ── Colour tab views ──────────────────────────────────────────────
          Expanded(
            child: ibcsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final pool = _filter == null
                    ? all
                    : all.where((b) => b.status == _filter).toList();

                return TabBarView(
                  controller: _tab,
                  children: [
                    for (final c in _kRegColours)
                      _RegisterColourTab(
                        ibcs: pool
                            .where((i) => i.itemCode == c)
                            .toList()
                          ..sort((a, b) =>
                              a.ibcNumber.compareTo(b.ibcNumber)),
                        colourLabel:
                            c[0].toUpperCase() + c.substring(1),
                        statusFilter: _filter,
                      ),
                  ],
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
        color:
            selected ? scheme.onPrimaryContainer : scheme.onSurface,
        fontWeight:
            selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

// ── Searchable IBC list for one colour tab ──────────────────────────────────

class _RegisterColourTab extends StatefulWidget {
  const _RegisterColourTab({
    required this.ibcs,
    required this.colourLabel,
    required this.statusFilter,
  });

  final List<InkIbc> ibcs;
  final String colourLabel;
  final InkIbcStatus? statusFilter;

  @override
  State<_RegisterColourTab> createState() => _RegisterColourTabState();
}

class _RegisterColourTabState extends State<_RegisterColourTab>
    with AutomaticKeepAliveClientMixin {
  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('d MMM yyyy');

  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final filtered = widget.ibcs
        .where((i) =>
            _query.isEmpty ||
            i.ibcNumber.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search IBC number…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 8, horizontal: 16),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      })
                  : null,
            ),
          ),
        ),
        // Count line
        if (widget.ibcs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text(
                  '${filtered.length} IBC${filtered.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (_query.isNotEmpty &&
                    filtered.length != widget.ibcs.length)
                  Text(
                    ' of ${widget.ibcs.length}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        // IBC list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _query.isNotEmpty
                          ? 'No IBCs match "$_query".'
                          : 'No ${widget.colourLabel} IBCs'
                              '${widget.statusFilter != null ? ' (${widget.statusFilter!.value})' : ''}.',
                      style:
                          TextStyle(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final ibc = filtered[i];
                    final consumed =
                        ibc.status == InkIbcStatus.transferred;

                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status icon
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 2, right: 12),
                            child: Icon(
                              consumed
                                  ? Icons.check_circle_outline
                                  : Icons.propane_tank_outlined,
                              size: 22,
                              color: consumed
                                  ? scheme.tertiary
                                  : scheme.primary,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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
                                // kg + charge
                                Text(
                                  [
                                    '${_qty.format(ibc.kg)} kg',
                                    if (ibc.chargeNumber != null)
                                      'Charge ${ibc.chargeNumber}',
                                  ].join(' · '),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                                const SizedBox(height: 2),
                                // Received date + supplier
                                Text(
                                  [
                                    'Received ${_df.format(ibc.receivedDate)}',
                                    if (ibc.supplierName != null)
                                      ibc.supplierName!,
                                  ].join(' · '),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color:
                                              scheme.onSurfaceVariant),
                                ),
                                if (ibc.orderNumber != null ||
                                    ibc.cgnaNumber != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (ibc.orderNumber != null)
                                        'Order ${ibc.orderNumber}',
                                      if (ibc.cgnaNumber != null)
                                        'CGNA ${ibc.cgnaNumber}',
                                    ].join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color:
                                                scheme.onSurfaceVariant),
                                  ),
                                ],
                                // Consumed date + wash
                                if (consumed) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      'Consumed ${ibc.transferredDate != null ? _df.format(ibc.transferredDate!) : '—'}',
                                      if (ibc.washTolulLitres != null)
                                        'Wash ${_qty.format(ibc.washTolulLitres!)} LTS',
                                    ].join(' · '),
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
                ),
        ),
      ],
    );
  }
}

// ── Status chip ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.scheme});
  final InkIbcStatus status;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final consumed = status == InkIbcStatus.transferred;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: consumed
            ? scheme.tertiaryContainer
            : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        consumed ? 'Consumed' : 'Received',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: consumed
                  ? scheme.onTertiaryContainer
                  : scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
