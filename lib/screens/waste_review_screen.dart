import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/waste_service.dart';
import '../models/waste_load.dart';
import '../models/waste_item.dart';
import '../models/waste_settings.dart';
import '../utils/role.dart' as role_utils;
import '../utils/formatters.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import 'waste_load_detail_screen.dart';

/// Admin cost review — loads in [pendingCostReview] after off-site weighbridge document.
class WasteReviewScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const WasteReviewScreen({super.key, this.embedded = false});

  @override
  ConsumerState<WasteReviewScreen> createState() => _WasteReviewScreenState();
}

class _WasteReviewScreenState extends ConsumerState<WasteReviewScreen> {
  final WasteService _wasteService = WasteService();
  List<WasteLoad> _pending = [];
  bool _isLoading = true;
  String? _error;
  WasteSettings? _wasteSettings;

  bool get _canAccess => role_utils.isWasteAdmin(currentEmployee);

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
  }

  Future<void> _loadFeatureStatus() async {
    final settings = await _wasteService.getWasteSettings();
    if (mounted) {
      setState(() => _wasteSettings = settings);
      if (_canAccess) _loadPending();
    }
  }

  Future<void> _loadPending() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _wasteService
          .watchPendingCostReview()
          .first
          .timeout(const Duration(seconds: 12), onTimeout: () => []);
      if (mounted) {
        setState(() {
          _pending = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess) {
      return const Center(child: Text('Access denied. Waste Admin only.'));
    }

    if (_wasteSettings != null && !_wasteSettings!.wasteEnabled) {
      return const Center(child: Text('WasteTrack is currently disabled.'));
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Load error: $_error'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadPending, child: const Text('Retry')),
          ],
        ),
      );
    }

    final body = RefreshIndicator(
      onRefresh: _loadPending,
      child: _pending.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No loads awaiting cost review.')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pending.length,
              itemBuilder: (context, i) => _LoadReviewCard(
                load: _pending[i],
                wasteService: _wasteService,
                onApproved: _loadPending,
              ),
            ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Cost Review')),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadReviewCard extends StatefulWidget {
  const _LoadReviewCard({
    required this.load,
    required this.wasteService,
    required this.onApproved,
  });

  final WasteLoad load;
  final WasteService wasteService;
  final VoidCallback onApproved;

  @override
  State<_LoadReviewCard> createState() => _LoadReviewCardState();
}

class _LoadReviewCardState extends State<_LoadReviewCard> {
  List<WasteItem> _items = [];
  bool _itemsLoading = true;
  StreamSubscription<List<WasteItem>>? _itemsSub;

  // Rate controllers keyed by item id.
  final Map<String, TextEditingController> _rateControllers = {};
  // Approved cost field (defaults to calculated total, admin can edit).
  late TextEditingController _approvedCtrl;
  // Set to true once the admin manually edits the approved field; stops rate
  // changes from auto-overwriting it.
  bool _approvedTouched = false;

  @override
  void initState() {
    super.initState();
    _approvedCtrl = TextEditingController();
    _itemsSub = widget.wasteService
        .watchItemsForLoad(widget.load.id!)
        .listen((items) {
      if (!mounted) return;
      setState(() {
        _items = items;
        _itemsLoading = false;
        // Seed rate controllers for any new items.
        for (final item in items) {
          _rateControllers.putIfAbsent(
            item.id!,
            () => TextEditingController(
              text: item.ratePerKg != null
                  ? item.ratePerKg!.toStringAsFixed(2)
                  : '',
            ),
          );
        }
        // Seed approved amount to calculated total if not yet set.
        if (_approvedCtrl.text.isEmpty) {
          final calc = _calculatedTotal;
          if (calc > 0) {
            _approvedCtrl.text = calc.toStringAsFixed(2);
          }
        }
      });
    }, onError: (_) {
      if (mounted) setState(() => _itemsLoading = false);
    });
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    for (final c in _rateControllers.values) { c.dispose(); }
    _approvedCtrl.dispose();
    super.dispose();
  }

  double _rateFor(WasteItem item) {
    final ctrl = _rateControllers[item.id!];
    if (ctrl == null) return item.ratePerKg ?? 0.0;
    return double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
  }

  double get _calculatedTotal {
    return _items.fold(0.0, (sum, item) => sum + item.weightKg * _rateFor(item));
  }

  Future<void> _approve() async {
    final approvedValue =
        double.tryParse(_approvedCtrl.text.replaceAll(',', '.'));
    if (approvedValue == null || approvedValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid approved cost (R ex VAT > 0)')),
      );
      return;
    }

    final calculatedTotal = _calculatedTotal;

    // Collect items where the admin set or changed the rate.
    final rateUpdates = <({
      String itemId,
      String subtype,
      double ratePerKg,
      String contractorId
    })>[];
    for (final item in _items) {
      final rate = _rateFor(item);
      if (rate > 0 && rate != item.ratePerKg) {
        rateUpdates.add((
          itemId: item.id!,
          subtype: item.subtype,
          ratePerKg: rate,
          contractorId: widget.load.contractorId,
        ));
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve cost?'),
        content: Text(
          'Load ${widget.load.loadNumber.isNotEmpty ? widget.load.loadNumber : widget.load.mainWasteType}\n'
          'Calculated: R ${calculatedTotal.toStringAsFixed(2)}\n'
          'Approved:   R ${approvedValue.toStringAsFixed(2)} ex VAT',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await widget.wasteService.approveCostReview(
        loadId: widget.load.id!,
        randValueExVat: approvedValue,
        reviewedBy: currentEmployee?.clockNo ?? 'admin',
        calculatedCost: calculatedTotal,
        itemRateUpdates: rateUpdates,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cost approved — load completed'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onApproved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final load = widget.load;
    final weight = load.actualWeighbridgeWeightKg;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Text(
              load.loadNumber.isNotEmpty
                  ? '${load.loadNumber} • ${load.mainWasteType}'
                  : load.mainWasteType,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '${load.contractorName ?? load.contractorId} • ${load.driverName}',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).appColors.textMuted),
            ),
            if (weight != null) ...[
              const SizedBox(height: 4),
              Text('Weighbridge: ${formatSAWeight(weight)}',
                  style: const TextStyle(fontSize: 13)),
            ],
            if (load.weighbridgeTicketWaived) ...[
              const SizedBox(height: 4),
              Text(
                'No ticket — waived by '
                '${load.weighbridgeTicketWaivedByName ?? load.weighbridgeTicketWaivedBy ?? 'unknown'}',
                style:
                    TextStyle(fontSize: 12, color: Colors.purple.shade800),
              ),
            ],
            if (load.weighbridgeTicketPhotoUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: load.weighbridgeTicketPhotoUrl!,
                  height: 80,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Itemized cost breakdown ──
            if (_itemsLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (_items.isEmpty)
              Text('No items recorded.',
                  style: TextStyle(
                      color: Theme.of(context).appColors.textMuted,
                      fontSize: 13))
            else
              _buildItemsTable(context),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ── Approved amount ──
            Text('Approved amount (edit to match accounts):',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).appColors.textMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _approvedCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cost (R ex VAT)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixText: 'R ',
              ),
              onChanged: (_) => setState(() { _approvedTouched = true; }),
            ),

            const SizedBox(height: 12),

            // ── Action row ──
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            WasteLoadDetailScreen(load: load)),
                  ).then((_) => widget.onApproved()),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Details'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _approve,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).appColors.wasteGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsTable(BuildContext context) {
    final calculatedTotal = _calculatedTotal;
    final textMuted = Theme.of(context).appColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Expanded(
                flex: 3,
                child: Text('Subtype',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textMuted))),
            Expanded(
                flex: 2,
                child: Text('Weight',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textMuted))),
            Expanded(
                flex: 3,
                child: Text('R/kg',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textMuted))),
            Expanded(
                flex: 2,
                child: Text('Value',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textMuted))),
          ],
        ),
        const SizedBox(height: 4),
        ..._items.map((item) {
          final rate = _rateFor(item);
          final lineValue = item.weightKg * rate;
          final ctrl = _rateControllers[item.id!]!;
          final missingRate = ctrl.text.trim().isEmpty;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                    flex: 3,
                    child: Text(item.subtype,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    flex: 2,
                    child: Text(formatSAWeight(item.weightKg),
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            border: const OutlineInputBorder(),
                            suffixIcon: missingRate
                                ? const Icon(Icons.warning_amber,
                                    color: Colors.orange, size: 16)
                                : null,
                          ),
                          onChanged: (_) => setState(() {
                            if (!_approvedTouched) {
                              _approvedCtrl.text =
                                  _calculatedTotal.toStringAsFixed(2);
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    rate > 0 ? 'R ${lineValue.toStringAsFixed(2)}' : '—',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: 12,
                        color: missingRate ? Colors.orange : null),
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(height: 16),
        Row(
          children: [
            Text('Calculated total',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textMuted)),
            const Spacer(),
            Text(
              'R ${calculatedTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}
