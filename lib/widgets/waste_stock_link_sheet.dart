import 'package:flutter/material.dart';

import '../models/waste_stock_item.dart';
import '../services/waste_service.dart';
import '../utils/formatters.dart';

/// Bottom sheet to pick on-site stock items for linking to a load.
class WasteStockLinkSheet extends StatefulWidget {
  const WasteStockLinkSheet({
    super.key,
    this.wasteType = 'Paper Waste',
    this.subtypeFilter,
    this.initialSelectedIds = const [],
    this.title = 'Link on-site stock',
    this.subtitle =
        'Select items for this load. For scheduled loads the guard sees them at collection.',
  });

  final String wasteType;
  final Set<String>? subtypeFilter;
  final List<String> initialSelectedIds;
  final String title;
  final String subtitle;

  static Future<List<String>?> show(
    BuildContext context, {
    String wasteType = 'Paper Waste',
    Set<String>? subtypeFilter,
    List<String> initialSelectedIds = const [],
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
  bool _loading = true;
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
          .watchStockOnSite(widget.wasteType)
          .first
          .timeout(const Duration(seconds: 12), onTimeout: () => []);
      if (mounted) {
        final filter = widget.subtypeFilter;
        setState(() {
          _stock = filter == null || filter.isEmpty
              ? items
              : items.where((i) => filter.contains(i.subtype)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
                    return InkWell(
                      onTap: () => setState(() {
                        if (selected) {
                          _selected.remove(id);
                        } else {
                          _selected.add(id);
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
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selected.add(id);
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.subtype,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    '${formatSADate(item.createdAt)} · ${item.createdByName}'
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()),
                  child: Text(
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