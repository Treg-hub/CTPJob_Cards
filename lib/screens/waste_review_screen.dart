import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/waste_service.dart';
import '../models/waste_load.dart';
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
  final Map<String, TextEditingController> _costControllers = {};

  bool get _canAccess => role_utils.isWasteAdmin(currentEmployee);

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
  }

  @override
  void dispose() {
    for (final c in _costControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFeatureStatus() async {
    final settings = await _wasteService.getWasteSettings();
    if (mounted) {
      setState(() => _wasteSettings = settings);
      if (_canAccess) _loadPending();
    }
  }

  TextEditingController _controllerFor(WasteLoad load) {
    return _costControllers.putIfAbsent(
      load.id!,
      () => TextEditingController(
        text: load.randValueExVat != null
            ? load.randValueExVat!.toStringAsFixed(2)
            : '',
      ),
    );
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

  Future<void> _approve(WasteLoad load) async {
    final ctrl = _controllerFor(load);
    final value = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid cost (R ex VAT)')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve cost?'),
        content: Text(
          'Mark load ${load.loadNumber.isNotEmpty ? load.loadNumber : load.mainWasteType} '
          'complete at R ${value.toStringAsFixed(2)} ex VAT?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _wasteService.approveCostReview(
        loadId: load.id!,
        randValueExVat: value,
        rate: load.rate,
        reviewedBy: currentEmployee?.clockNo ?? 'admin',
      );
      _costControllers.remove(load.id!)?.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cost approved — load completed'), backgroundColor: Colors.green),
        );
        _loadPending();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
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
              itemBuilder: (context, i) {
                final load = _pending[i];
                final ctrl = _controllerFor(load);
                final weight = load.actualWeighbridgeWeightKg;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          load.loadNumber.isNotEmpty
                              ? '${load.loadNumber} • ${load.mainWasteType}'
                              : load.mainWasteType,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${load.contractorName ?? load.contractorId} • ${load.driverName}',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).appColors.textMuted),
                        ),
                        if (weight != null) ...[
                          const SizedBox(height: 4),
                          Text('Weighbridge: ${formatSAWeight(weight)}',
                              style: const TextStyle(fontSize: 13)),
                        ],
                        if (load.weighbridgeTicketWaived) ...[
                          const SizedBox(height: 4),
                          Text(
                            'No weighbridge ticket — waived by '
                            '${load.weighbridgeTicketWaivedByName ?? load.weighbridgeTicketWaivedBy ?? 'unknown'}',
                            style: TextStyle(fontSize: 12, color: Colors.purple.shade800),
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
                        const SizedBox(height: 10),
                        if (load.rate != null)
                          Text(
                            'Suggested rate: R ${load.rate!.toStringAsFixed(2)}/kg',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
                          ),
                        TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Cost (R ex VAT)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixText: 'R ',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: load)),
                              ).then((_) => _loadPending()),
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('Details'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: () => _approve(load),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Approve'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context).appColors.wasteGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Cost Review')),
      body: body,
    );
  }
}