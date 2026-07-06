import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/ink_stock_item.dart';
import '../models/ink_transaction.dart';
import '../models/ink_txn_type.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/ink_period_guard.dart';
import '../utils/persona_audit.dart';
import '../utils/ink_pickers.dart';
import '../utils/screen_insets.dart';

/// Phase 1g — Toloul Recovery. Records solvent recovered from the Lurgi
/// distillation as a `recovery` transaction (additive, valued at the CURRENT
/// WAC — recovery never moves WAC). Recent entries are shown below the form
/// so the operator can confirm what was last entered.
class InkTolulRecoveryScreen extends ConsumerStatefulWidget {
  const InkTolulRecoveryScreen({super.key});

  @override
  ConsumerState<InkTolulRecoveryScreen> createState() => _State();
}

class _State extends ConsumerState<InkTolulRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  String? _itemCode;
  DateTime _effectiveAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await pickInkDateTime(context, _effectiveAt);
    if (dt != null) setState(() => _effectiveAt = dt);
  }

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate() || _itemCode == null) return;
    if (!guardPersonaSubmit(context)) return;
    final allowed =
        await confirmClosedPeriodOverride(context, ref, _effectiveAt);
    if (!allowed) return;
    setState(() => _submitting = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    final txn = InkTransaction(
      type: InkTxnType.recovery,
      stockItemCode: _itemCode!,
      quantityDelta: double.parse(_qtyCtrl.text.trim()),
      effectiveAt: _effectiveAt,
      costStatus: InkCostStatus.na,
      lurgiSource: _sourceCtrl.text.trim().isEmpty
          ? null
          : _sourceCtrl.text.trim(),
      actorClockNo: emp?.clockNo ?? '',
      actorName: emp?.name ?? '',
      idempotencyKey: const Uuid().v4(),
    );
    try {
      await ref.read(inkServiceProvider).recordTransaction(txn);
      if (!mounted) return;
      _qtyCtrl.clear();
      _sourceCtrl.clear();
      setState(() {
        _effectiveAt = DateTime.now();
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recovery recorded.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inkStockItemsProvider);
    final recentAsync = ref.watch(inkRecentRecoveriesCurrentPeriodProvider);
    final df = DateFormat('EEE d MMM yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Toloul Recovery')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allItems) {
          final items = allItems
              .where((i) => i.itemClass == InkItemClass.solvent)
              .toList();
          if (_itemCode == null && items.length == 1) {
            _itemCode = items.first.itemCode;
          }
          InkStockItem? selected;
          for (final i in items) {
            if (i.itemCode == _itemCode) selected = i;
          }
          return ListView(
            padding: ScreenInsets.symmetricScroll(context),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _itemCode,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Solvent'),
                      items: [
                        for (final i in items)
                          DropdownMenuItem(
                              value: i.itemCode,
                              child: Text('${i.displayName} (${i.unit})')),
                      ],
                      onChanged: (v) => setState(() => _itemCode = v),
                      validator: (v) =>
                          v == null ? 'Select the solvent' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Volume recovered',
                        suffixText: selected?.unit ?? 'LTS',
                      ),
                      validator: (v) {
                        final d = double.tryParse((v ?? '').trim());
                        if (d == null || d <= 0) {
                          return 'Enter a volume greater than 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sourceCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Lurgi / source (optional)'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label:
                          Text('Effective date: ${df.format(_effectiveAt)}'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          alignment: Alignment.centerLeft),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Record recovery'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                    ),
                  ],
                ),
              ),

              // ── Recent recoveries ─────────────────────────────────────────
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 4),
              Text('Recoveries this period',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              ...recentAsync.when(
                loading: () => [const LinearProgressIndicator()],
                error: (_, __) => [],
                data: (recoveries) {
                  if (recoveries.isEmpty) {
                    return [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No recoveries in the current period.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ];
                  }
                  return [
                    for (final r in recoveries)
                      _RecoveryTile(txn: r, item: selected),
                  ];
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

// ── Recent recovery tile ──────────────────────────────────────────────────────

class _RecoveryTile extends StatelessWidget {
  const _RecoveryTile({required this.txn, required this.item});

  static final _df = DateFormat('d MMM yy HH:mm');
  static final _qty = NumberFormat('#,##0.##');

  final InkTransaction txn;
  final InkStockItem? item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = item?.unit ?? 'LTS';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 12, top: 1),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.recycling,
                size: 16, color: scheme.onPrimaryContainer),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_qty.format(txn.quantityDelta)} $unit recovered'
                        '${txn.lurgiSource != null ? ' · ${txn.lurgiSource}' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (txn.seqNumber != null)
                      Text(
                        txn.seqNumber!,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _df.format(txn.effectiveAt),
                    if (txn.actorName.isNotEmpty) txn.actorName,
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
