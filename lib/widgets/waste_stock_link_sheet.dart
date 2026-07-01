import 'package:flutter/material.dart';

import '../models/waste_stock_item.dart';
import '../models/waste_stock_source.dart';
import '../services/waste_service.dart';
import '../utils/formatters.dart';
import '../utils/waste_stock_mapping.dart';

/// Bottom sheet to pick on-site stock items for linking to a load.
class WasteStockLinkSheet extends StatefulWidget {
  const WasteStockLinkSheet({
    super.key,
    this.wasteType = 'Paper Waste',
    this.subtypeFilter,
    this.initialSelectedIds = const [],
    this.includeManagerOnlyStock = false,
    this.title = 'Link on-site stock',
    this.subtitle =
        'Select items for this load. For scheduled loads the guard sees them at collection.',
  });

  final String wasteType;
  final Set<String>? subtypeFilter;
  final List<String> initialSelectedIds;
  /// Collection-day linking may include manager-only stock (e.g. copper) for guards.
  final bool includeManagerOnlyStock;
  final String title;
  final String subtitle;

  static Future<List<String>?> show(
    BuildContext context, {
    String wasteType = 'Paper Waste',
    Set<String>? subtypeFilter,
    List<String> initialSelectedIds = const [],
    bool includeManagerOnlyStock = false,
    String title = 'Link on-site stock',
    String? subtitle,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: WasteStockLinkSheet(
          wasteType: wasteType,
          subtypeFilter: subtypeFilter,
          initialSelectedIds: initialSelectedIds,
          includeManagerOnlyStock: includeManagerOnlyStock,
          title: title,
          subtitle: subtitle ??
              'Select items for this load. For scheduled loads the guard sees them at collection.',
        ),
      ),
    );
  }

  @override
  State<WasteStockLinkSheet> createState() => _WasteStockLinkSheetState();
}

class _WasteStockLinkSheetState extends State<WasteStockLinkSheet> {
  final WasteService _wasteService = WasteService();
  final Set<String> _selected = {};
  /// How many units to take for each selected multi-unit (IBC pool/split,
  /// `quantity > 1`) item — defaults to the full on-site quantity. Items not
  /// present here, or with `quantity == 1`, are taken whole as before.
  final Map<String, int> _takeQty = {};
  bool _loading = true;
  bool _saving = false;
  List<WasteStockItem> _stock = [];

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelectedIds);
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _wasteService
          .watchAllStockOnSite()
          .first
          .timeout(const Duration(seconds: 12), onTimeout: () => []);
      if (mounted) {
        final filter = widget.subtypeFilter;
        var visible = items;
        if (!widget.includeManagerOnlyStock) {
          visible = visible
              .where((i) => i.visibility != WasteStockVisibility.managerOnly)
              .toList();
        }
        setState(() {
          _stock = filter == null || filter.isEmpty
              ? visible
              : visible
                  .where((i) => stockItemMatchesFilter(i, filter))
                  .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// For every selected multi-unit item, splits off the chosen take-quantity
  /// into a fresh doc (always — even when taking the full on-site quantity,
  /// see [WasteService.splitPoolStock] doc comment for why) and substitutes
  /// that new doc's id in the returned selection. Single-unit / non-pool
  /// items pass through unchanged.
  Future<void> _confirmSelection() async {
    if (_selected.isEmpty) {
      if (mounted) Navigator.pop(context, <String>[]);
      return;
    }
    final multiUnitSelections = _selected.where((id) {
      final item = _stock.firstWhere((s) => s.id == id, orElse: () => _stock.first);
      return item.id == id && item.isQuantityOnlyType && item.quantity > 1;
    }).toList();

    if (multiUnitSelections.isEmpty) {
      if (mounted) Navigator.pop(context, _selected.toList());
      return;
    }

    setState(() => _saving = true);
    final result = <String>[];
    try {
      for (final id in _selected) {
        if (multiUnitSelections.contains(id)) {
          final newId = await _wasteService.splitPoolStock(
            poolStockId: id,
            takeQty: _takeQty[id]!,
          );
          result.add(newId);
        } else {
          result.add(id);
        }
      }
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not take stock: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(widget.subtitle,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_stock.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No on-site stock for ${widget.wasteType}.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _stock.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final item = _stock[i];
                    final id = item.id!;
                    final selected = _selected.contains(id);
                    final isMultiUnit = item.isQuantityOnlyType && item.quantity > 1;
                    final takeQty = _takeQty[id] ?? item.quantity;
                    return InkWell(
                      onTap: () => setState(() {
                        if (selected) {
                          _selected.remove(id);
                          _takeQty.remove(id);
                        } else {
                          _selected.add(id);
                          if (isMultiUnit) _takeQty[id] = item.quantity;
                        }
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).dividerColor,
                            width: selected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: selected,
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _selected.add(id);
                                      if (isMultiUnit) _takeQty[id] = item.quantity;
                                    } else {
                                      _selected.remove(id);
                                      _takeQty.remove(id);
                                    }
                                  }),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.ibcNumber != null
                                            ? 'IBC ${item.ibcNumber}'
                                            : (item.subtype.isNotEmpty
                                                ? item.subtype
                                                : item.wasteType),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        '${formatSADate(item.createdAt)} · ${item.createdByName}'
                                        '${item.isQuantityOnlyType ? ' · qty ${item.quantity}' : ''}'
                                        '${item.estimatedWeightKg != null ? ' · ~${formatSAWeight(item.estimatedWeightKg!)}' : ''}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (selected && isMultiUnit)
                              Padding(
                                padding: const EdgeInsets.only(left: 40, bottom: 4),
                                child: Row(
                                  children: [
                                    Text('Take:', style: Theme.of(context).textTheme.bodySmall),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: takeQty > 1
                                          ? () => setState(() => _takeQty[id] = takeQty - 1)
                                          : null,
                                    ),
                                    Text('$takeQty of ${item.quantity}',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: takeQty < item.quantity
                                          ? () => setState(() => _takeQty[id] = takeQty + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _confirmSelection,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _selected.isEmpty
                              ? 'Clear selection'
                              : 'Save (${_selected.length})',
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}