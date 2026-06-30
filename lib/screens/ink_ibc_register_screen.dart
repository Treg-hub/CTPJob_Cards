import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../theme/app_theme.dart';
import '../utils/ink_period_guard.dart';
import '../utils/persona_audit.dart';
import '../utils/role.dart' as role_utils;

/// IBC register — **This period** summary tab (consumed grouped by colour) plus
/// colour tabs for the full register (search, status filter, manager void).
class InkIbcRegisterScreen extends ConsumerStatefulWidget {
  const InkIbcRegisterScreen({super.key});

  @override
  ConsumerState<InkIbcRegisterScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcRegisterScreen>
    with SingleTickerProviderStateMixin {
  static const _summaryTabIndex = 0;

  late final TabController _tab;

  /// null = All (colour tabs only)
  InkIbcStatus? _filter;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: kInkColourCodes.length + 1,
      vsync: this,
    );
    _tab.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tab.indexIsChanging) return;
    if (_tab.index == _summaryTabIndex && _filter != null) {
      setState(() => _filter = null);
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  Future<void> _voidIbc(InkIbc ibc) async {
    if (!guardPersonaSubmit(context)) return;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void IBC consumption?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IBC ${ibc.ibcNumber} returns to "received" and its wash '
                'toloul is reversed.'),
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
              child: const Text('Void')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a reason for the void.')));
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    final allowed = await confirmClosedPeriodOverride(
        context, ref, ibc.transferredDate ?? ibc.receivedDate);
    if (!allowed || !mounted) return;
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).voidIbcTransfer(
            ibc,
            reason: reason,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('IBC consumption voided — back to received.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ibcsAsync = ref.watch(inkAllIbcsProvider);
    final consumedThisPeriod = ref.watch(inkIbcsConsumedThisPeriodProvider);
    final isManager =
        role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    final onSummaryTab = _tab.index == _summaryTabIndex;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IBC Register'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          tabs: [
            Tab(
              text: consumedThisPeriod.isEmpty
                  ? 'This period'
                  : 'This period (${consumedThisPeriod.length})',
            ),
            for (final l in kInkColourLabels) Tab(text: l),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!onSummaryTab) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    _filterChip(context, null, 'All'),
                    _filterChip(context, InkIbcStatus.received, 'Received'),
                    _filterChip(context, InkIbcStatus.transferred, 'Consumed'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
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
                    _PeriodSummaryTab(ibcs: consumedThisPeriod),
                    for (final c in kInkColourCodes)
                      _RegisterColourTab(
                        ibcs: pool
                            .where((i) => i.itemCode == c)
                            .toList()
                          ..sort((a, b) =>
                              a.ibcNumber.compareTo(b.ibcNumber)),
                        colourLabel:
                            c[0].toUpperCase() + c.substring(1),
                        statusFilter: _filter,
                        onVoid: isManager ? _voidIbc : null,
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
        color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

// ── This period summary ───────────────────────────────────────────────────────

class _PeriodSummaryTab extends StatelessWidget {
  const _PeriodSummaryTab({required this.ibcs});
  final List<InkIbc> ibcs;

  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (ibcs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No IBCs consumed in the current period yet.',
            style: TextStyle(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final byColour = <String, List<InkIbc>>{};
    for (final ibc in ibcs) {
      byColour.putIfAbsent(ibc.itemCode, () => []).add(ibc);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Consumed since last count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 12),
        for (final code in kInkColourCodes)
          if (byColour[code]?.isNotEmpty == true) ...[
            _ColourSection(
              label: kInkColourLabels[kInkColourCodes.indexOf(code)],
              ibcs: byColour[code]!,
              qty: _qty,
              df: _df,
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _ColourSection extends StatelessWidget {
  const _ColourSection({
    required this.label,
    required this.ibcs,
    required this.qty,
    required this.df,
  });

  final String label;
  final List<InkIbc> ibcs;
  final NumberFormat qty;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < ibcs.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: _PeriodIbcRow(ibc: ibcs[i], qty: qty, df: df),
                ),
              ],
            ],
          ),
        ),
        Text(
          '${ibcs.length} consumed',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PeriodIbcRow extends StatelessWidget {
  const _PeriodIbcRow({
    required this.ibc,
    required this.qty,
    required this.df,
  });

  final InkIbc ibc;
  final NumberFormat qty;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wash = ibc.washTolulLitres;
    final washText = wash != null && wash > 0
        ? '${qty.format(wash)} L wash'
        : 'No wash';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${ibc.ibcNumber} · ${qty.format(ibc.kg)} kg · $washText',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          ibc.transferredDate != null
              ? df.format(ibc.transferredDate!)
              : 'Date unknown',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ── Searchable IBC list for one colour tab ──────────────────────────────────

class _RegisterColourTab extends StatefulWidget {
  const _RegisterColourTab({
    required this.ibcs,
    required this.colourLabel,
    required this.statusFilter,
    this.onVoid,
  });

  final List<InkIbc> ibcs;
  final String colourLabel;
  final InkIbcStatus? statusFilter;
  final void Function(InkIbc)? onVoid;

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
                      style: TextStyle(color: scheme.onSurfaceVariant),
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

                    final row = Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 2, right: 12),
                            child: Icon(
                              consumed
                                  ? Icons.check_circle_outline
                                  : Icons.propane_tank_outlined,
                              size: 22,
                              color: consumed
                                  ? Theme.of(context).appColors.statusCompleted
                                  : scheme.primary,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ibc.ibcNumber,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    _StatusChip(
                                        status: ibc.status, scheme: scheme),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    '${_qty.format(ibc.kg)} kg',
                                    if (ibc.chargeNumber != null)
                                      'Charge ${ibc.chargeNumber}',
                                  ].join(' · '),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
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
                                          color: scheme.onSurfaceVariant),
                                ),
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
                                            color: Theme.of(context)
                                                .appColors
                                                .statusCompleted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    return (consumed && widget.onVoid != null)
                        ? InkWell(
                            onTap: () => widget.onVoid!(ibc),
                            child: row,
                          )
                        : row;
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.scheme});
  final InkIbcStatus status;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final consumed = status == InkIbcStatus.transferred;
    final chipColor = consumed
        ? Theme.of(context).appColors.statusCompleted
        : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        consumed ? 'Consumed' : 'Received',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}