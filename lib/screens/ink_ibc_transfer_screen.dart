import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/ink_pickers.dart';


/// Phase 1c — Consume IBC (transfer IBC → tank). Colour tabs let the operator
/// pick the specific IBC by number, set the date/time, and record the toloul
/// used to wash the emptied IBC. A `consumption_toloul_wash` txn is written;
/// stock is unaffected (it was counted at receipt).
class InkIbcTransferScreen extends ConsumerStatefulWidget {
  const InkIbcTransferScreen({super.key});

  @override
  ConsumerState<InkIbcTransferScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcTransferScreen>
    with SingleTickerProviderStateMixin {
  static final _qty = NumberFormat('#,##0.##');
  static final _df = DateFormat('EEE d MMM yyyy HH:mm');

  late final TabController _tab;
  final _washCtrl = TextEditingController();
  String? _selectedNumber;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: kInkColourCodes.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _washCtrl.dispose();
    super.dispose();
  }

  void _toggleSelect(InkIbc ibc) =>
      setState(() => _selectedNumber =
          _selectedNumber == ibc.ibcNumber ? null : ibc.ibcNumber);

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit(InkIbc ibc, String tolulItemCode) async {
    final wash = double.tryParse(_washCtrl.text.trim()) ?? 0;
    if (wash < 0) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).transferIbc(
            ibc: ibc,
            tolulItemCode: tolulItemCode,
            washLitres: wash,
            effectiveAt: _effectiveAt,
            actorClockNo: emp?.clockNo ?? '',
            actorName: emp?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IBC consumed; wash recorded.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ibcsAsync = ref.watch(inkReceivedIbcsProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final scheme = Theme.of(context).colorScheme;

    String? tolulItemCode;
    for (final i in items) {
      if (i.itemClass == InkItemClass.solvent) { tolulItemCode = i.itemCode; break; }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consume IBC'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          tabs: [for (final l in kInkColourLabels) Tab(text: l)],
        ),
      ),
      body: ibcsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          InkIbc? selected;
          for (final ibc in all) {
            if (ibc.ibcNumber == _selectedNumber) selected = ibc;
          }

          return Column(
            children: [
              // ── Colour tabs ───────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    for (final c in kInkColourCodes)
                      _IbcPickList(
                        ibcs: all.where((i) => i.itemCode == c).toList()
                          ..sort((a, b) => a.ibcNumber.compareTo(b.ibcNumber)),
                        selectedNumber: _selectedNumber,
                        onTap: _toggleSelect,
                        qty: _qty,
                        emptyLabel:
                            'No ${c[0].toUpperCase()}${c.substring(1)} IBCs awaiting consumption.',
                      ),
                  ],
                ),
              ),

              // ── Action panel (visible when an IBC is selected) ────────────
              if (selected != null) ...[
                const Divider(height: 1),
                ColoredBox(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Selected IBC heading
                        Row(
                          children: [
                            Icon(Icons.propane_tank_outlined,
                                size: 18, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'IBC ${selected.ibcNumber} · ${_qty.format(selected.kg)} kg',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _selectedNumber = null),
                              tooltip: 'Deselect',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Toloul + date row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _washCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Toloul wash',
                                  suffixText: 'LTS',
                                  helperText: 'Leave blank if no wash used',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.event, size: 16),
                              label: Text(
                                _df.format(_effectiveAt),
                                style: const TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 13),
                              ),
                            ),
                          ],
                        ),
                        if (tolulItemCode == null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'No toloul item found — wash cannot be recorded.',
                            style: TextStyle(
                                fontSize: 12, color: scheme.error),
                          ),
                        ],
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed:
                              (_submitting || tolulItemCode == null)
                                  ? null
                                  : () => _submit(selected!, tolulItemCode!),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.check),
                          label: const Text('Consume IBC'),
                          style: FilledButton.styleFrom(
                              minimumSize:
                                  const Size(double.infinity, 44)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── Searchable, selectable IBC list for one colour tab ─────────────────────

class _IbcPickList extends StatefulWidget {
  const _IbcPickList({
    required this.ibcs,
    required this.selectedNumber,
    required this.onTap,
    required this.qty,
    required this.emptyLabel,
  });

  final List<InkIbc> ibcs;
  final String? selectedNumber;
  final void Function(InkIbc) onTap;
  final NumberFormat qty;
  final String emptyLabel;

  @override
  State<_IbcPickList> createState() => _IbcPickListState();
}

class _IbcPickListState extends State<_IbcPickList>
    with AutomaticKeepAliveClientMixin {
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
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
        // Count badge
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
                if (_query.isNotEmpty && filtered.length != widget.ibcs.length)
                  Text(
                    ' of ${widget.ibcs.length}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        // List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _query.isNotEmpty
                          ? 'No IBCs match "$_query".'
                          : widget.emptyLabel,
                      style:
                          TextStyle(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 52),
                  itemBuilder: (_, idx) {
                    final ibc = filtered[idx];
                    final sel = ibc.ibcNumber == widget.selectedNumber;
                    return ListTile(
                      selected: sel,
                      selectedTileColor:
                          scheme.primaryContainer.withValues(alpha: 0.35),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      leading: Icon(
                        sel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: sel
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                      title: Text(
                        ibc.ibcNumber,
                        style: TextStyle(
                          fontWeight: sel
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        [
                          '${widget.qty.format(ibc.kg)} kg',
                          if (ibc.chargeNumber != null)
                            'Charge ${ibc.chargeNumber}',
                          if (ibc.orderNumber != null)
                            'Order ${ibc.orderNumber}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => widget.onTap(ibc),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
