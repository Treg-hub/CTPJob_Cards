import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/waste_load.dart';
import '../models/waste_item.dart';
import '../models/waste_type.dart';
import '../utils/deviation.dart';
import '../utils/formatters.dart';
import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';
import 'waste_signature_screen.dart';
import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../services/connectivity_service.dart';
import '../constants/collections.dart';

/// View / edit a single Waste Load.
/// Supports weighbridge entry, deviation display, item deletion (role-gated),
/// adding items to in-progress loads, and driver-signature completion.
class WasteLoadDetailScreen extends ConsumerStatefulWidget {
  final WasteLoad load;

  const WasteLoadDetailScreen({super.key, required this.load});

  @override
  ConsumerState<WasteLoadDetailScreen> createState() => _WasteLoadDetailScreenState();
}

class _WasteLoadDetailScreenState extends ConsumerState<WasteLoadDetailScreen> {
  final WasteService _wasteService = WasteService();
  late WasteLoad _currentLoad;
  final _weighbridgeController = TextEditingController();
  bool _isAdmin = false;
  bool _isManager = false;
  bool _isSaving = false;
  List<WasteType> _wasteTypes = [];

  @override
  void initState() {
    super.initState();
    _currentLoad = widget.load;
    _isAdmin = role_utils.isWasteAdmin(currentEmployee);
    if (_currentLoad.actualWeighbridgeWeightKg != null) {
      _weighbridgeController.text = _currentLoad.actualWeighbridgeWeightKg!.toString();
    }
    _wasteService.processOfflineWasteQueue();
    _wasteService.getWasteSettings().then((s) {
      if (mounted) {
        setState(() => _isManager = role_utils.isSecurityManager(currentEmployee, s));
      }
    });
    _wasteService.watchWasteTypes().first.then((types) {
      if (mounted) setState(() => _wasteTypes = types);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _weighbridgeController.dispose();
    super.dispose();
  }

  bool get _isCompleted => _currentLoad.status == WasteLoadStatus.completed;
  bool get _canManageItems => _isAdmin || _isManager;

  /// Can a user delete a specific item?
  bool _canDelete(WasteItem item) {
    if (_isCompleted) return _isAdmin; // only admin on completed loads
    return _canManageItems;
  }

  void _calculateAndShowDeviation() {
    final actual = double.tryParse(_weighbridgeController.text) ?? 0;
    if (actual <= 0) return;

    final recorded = _currentLoad.recordedWeightKg > 0 ? _currentLoad.recordedWeightKg : 0.0;
    final result = calculateDeviation(
      recordedWeightKg: recorded > 0 ? recorded : actual,
      actualWeightKg: actual,
    );

    final bool isDev = result.isDeviation;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(isDev ? Icons.warning_amber : Icons.check_circle,
                color: isDev ? Colors.red : Colors.green),
            const SizedBox(width: 8),
            Text(isDev ? 'DEVIATION ALERT' : 'Variance within thresholds'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recorded (items): ${formatSAWeight(result.recordedWeightKg)}'),
            Text('Actual (weighbridge): ${formatSAWeight(result.actualWeightKg)}'),
            const SizedBox(height: 8),
            Text('Variance: ${formatSAWeight(result.varianceKg)}  (${result.variancePercent.toStringAsFixed(1)}%)'),
            Text(
              'Thresholds: ${result.thresholdPercent.toStringAsFixed(0)}% or ${result.thresholdKg.toStringAsFixed(0)} kg',
              style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
            ),
            if (isDev)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                ),
                child: const Text(
                  '⚠️ EXCEEDS THRESHOLDS — Admin review required.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _saveWeighbridge() async {
    if (!_isAdmin && !_isManager) return;

    final weight = double.tryParse(_weighbridgeController.text);
    if (weight == null || weight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid positive weight')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _wasteService.saveWeighbridgeWeight(
        loadId: _currentLoad.id!,
        actualWeightKg: weight,
        updatedBy: currentEmployee?.clockNo,
      );

      setState(() {
        _currentLoad = _currentLoad.copyWith(actualWeighbridgeWeightKg: weight);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Weighbridge weight saved'),
            backgroundColor: Colors.green,
          ),
        );
        _calculateAndShowDeviation();

        final actual = weight;
        final recorded = _currentLoad.recordedWeightKg > 0 ? _currentLoad.recordedWeightKg : actual;
        final dev = calculateDeviation(recordedWeightKg: recorded, actualWeightKg: actual);
        if (dev.isDeviation) {
          await SyncService().addToQueue(
            collection: Collections.wasteAudit,
            operation: 'create',
            data: {
              'load_id': _currentLoad.id,
              'load_number': _currentLoad.loadNumber,
              'action': 'weighbridge_deviation',
              'recorded_weight_kg': recorded,
              'actual_weight_kg': actual,
              'variance_kg': dev.varianceKg,
              'variance_percent': dev.variancePercent,
              'triggered_by': currentEmployee?.clockNo ?? 'unknown',
              'created_at': DateTime.now().toIso8601String(),
            },
          );
          await SyncService().processNow();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removePhoto(WasteItem item, String photoUrl) async {
    if (item.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Photo?'),
        content: Text(
          'Remove this photo from "${item.subtype}"? '
          'The image will be deleted from storage.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _wasteService.removePhotoFromWasteItem(
        itemId: item.id!,
        photoUrl: photoUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo removed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteItem(WasteItem item) async {
    final isCompleted = _isCompleted;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text(
          isCompleted
              ? 'This load is completed. Deleting "${item.subtype}" is permanent and cannot be undone.'
              : 'Remove "${item.subtype}" (${item.weightKg.toStringAsFixed(1)} kg) from this load?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || item.id == null) return;

    try {
      await _wasteService.deleteWasteItem(item.id!, sourceStockId: item.sourceStockId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addItem() async {
    final typeNames = _wasteTypes.map((t) => t.mainType).toList();
    final result = await showModalBottomSheet<_NewItemResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: _AddItemSheet(
            typeNames: typeNames,
            defaultType: _currentLoad.mainWasteType,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _wasteService.addItemToExistingLoad(
        loadId: _currentLoad.id!,
        subtype: result.subtype,
        weightKg: result.weightKg,
        quantity: result.quantity,
        notes: result.notes,
        localPhotoPaths: result.localPhotoPaths,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item added'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add item: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _markComplete() async {
    setState(() => _isSaving = true);
    try {
      await _wasteService.markLoadComplete(
        _currentLoad.id!,
        completedBy: currentEmployee?.clockNo ?? 'unknown',
      );
      setState(() {
        _currentLoad = _currentLoad.copyWith(
          status: WasteLoadStatus.completed,
          completedBy: currentEmployee?.clockNo,
          completedAt: DateTime.now(),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Load marked complete'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEditWeighbridge = _isAdmin || _isManager;
    final statusColor = _statusColor(_currentLoad.status);
    final recorded = _currentLoad.recordedWeightKg;
    final actual = _currentLoad.actualWeighbridgeWeightKg;

    return Scaffold(
      appBar: WasteAppBar(
        title: _currentLoad.loadNumber.isNotEmpty ? _currentLoad.loadNumber : 'Load Detail',
        isOnSite: currentEmployee?.isOnSite,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Pending weighbridge action banner ──────────────
          if (_currentLoad.status == WasteLoadStatus.pendingWeighbridge && canEditWeighbridge)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade600, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.scale, color: Colors.amber.shade800, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Weighbridge entry required',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 14)),
                        Text('Enter the actual weighbridge weight below to complete this load.',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── Completed lock banner ─────────────────────────
          if (_isCompleted)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade400),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.green.shade700, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isAdmin
                          ? 'Load is completed and locked. Admin can still delete items.'
                          : 'Load is completed and locked. Contact admin to make changes.',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            ),

          // ── Status stepper ────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _WasteStatusStepper(status: _currentLoad.status),
          ),

          // ── Status banner ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(_statusIcon(_currentLoad.status), color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_currentLoad.mainWasteType,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(_currentLoad.status.displayLabel,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Info card ─────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.person, 'Driver',
                      _currentLoad.driverName.isNotEmpty ? _currentLoad.driverName : '—'),
                  const Divider(height: 16),
                  _infoRow(Icons.local_shipping, 'Vehicle',
                      _currentLoad.vehicleReg.isNotEmpty ? _currentLoad.vehicleReg : '—'),
                  const Divider(height: 16),
                  _infoRow(Icons.business, 'Contractor',
                      (_currentLoad.contractorName?.isNotEmpty == true)
                          ? _currentLoad.contractorName!
                          : (_currentLoad.contractorId.isNotEmpty ? _currentLoad.contractorId : '—')),
                  const Divider(height: 16),
                  _infoRow(Icons.calendar_today, 'Date', formatSADate(_currentLoad.dateTime)),
                  if (_currentLoad.collectedBy != null) ...[
                    const Divider(height: 16),
                    _infoRow(Icons.badge, 'Collected by',
                        _currentLoad.collectedByName?.isNotEmpty == true
                            ? _currentLoad.collectedByName!
                            : _currentLoad.collectedBy!),
                  ],
                ],
              ),
            ),
          ),

          // ── Items section ─────────────────────────────────
          const SizedBox(height: 12),
          if (_currentLoad.id != null)
            StreamBuilder<List<WasteItem>>(
              stream: _wasteService.watchItemsForLoad(_currentLoad.id!),
              builder: (context, snap) {
                final items = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }

                final canAdd = _canManageItems && !_isCompleted;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Waste Items (${items.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            if (canAdd)
                              TextButton.icon(
                                onPressed: _isSaving ? null : _addItem,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add'),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                          ],
                        ),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('No items recorded.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          )
                        else ...[
                          const SizedBox(height: 8),
                          ...items.map((item) => _ItemRow(
                            item: item,
                            canDelete: _canDelete(item),
                            canRemovePhotos: _canDelete(item),
                            onDelete: () => _deleteItem(item),
                            onRemovePhoto: (url) => _removePhoto(item, url),
                          )),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),

          // ── Weight card ───────────────────────────────────
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weight', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _weightBox('Recorded\n(items)', recorded > 0 ? formatSAWeight(recorded) : '—', Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _weightBox('Weighbridge', actual != null ? formatSAWeight(actual) : '—', actual != null ? Colors.green : Colors.grey)),
                    ],
                  ),
                  if (recorded > 0 && actual != null) ...[
                    const SizedBox(height: 10),
                    Builder(builder: (ctx) {
                      final diff = actual - recorded;
                      final pct = (diff / recorded * 100);
                      final isOk = diff.abs() <= recorded * 0.05 && diff.abs() <= 50;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isOk ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isOk ? Colors.green.shade400 : Colors.red.shade400),
                        ),
                        child: Row(
                          children: [
                            Icon(isOk ? Icons.check_circle : Icons.warning_amber,
                                color: isOk ? Colors.green : Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Variance: ${diff >= 0 ? '+' : ''}${formatSAWeight(diff)}  (${pct.abs().toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isOk ? Colors.green.shade800 : Colors.red.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

          // ── Weighbridge entry ─────────────────────────────
          if (canEditWeighbridge &&
              _currentLoad.status != WasteLoadStatus.completed &&
              _currentLoad.status != WasteLoadStatus.cancelled) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weighbridge Entry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _weighbridgeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Actual Weight (kg)',
                        border: OutlineInputBorder(),
                        suffixText: 'kg',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveWeighbridge,
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.scale),
                        label: Text(_isSaving ? 'Saving...' : 'Save Weighbridge Weight'),
                        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Signature & completion ─────────────────────────
          // draft: capture new signature + mark complete
          if (_currentLoad.status == WasteLoadStatus.draft) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _completeDraft,
                icon: const Icon(Icons.draw),
                label: const Text('Mark Complete & Capture Driver Signature'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],

          // pending_weighbridge: signature already on file — manager just marks complete
          if (_currentLoad.status == WasteLoadStatus.pendingWeighbridge && canEditWeighbridge) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Mark Load Complete?'),
                      content: const Text('This will finalise the load. Ensure the weighbridge weight has been saved first.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
                      ],
                    ),
                  );
                  if (ok == true) await _markComplete();
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark Load Complete'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
          ],

          if (_isAdmin) ...[
            const SizedBox(height: 16),
            Text('Admin: soft-delete (load level) available in a future version.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Draft-load completion: capture signature then mark complete (original flow).
  Future<void> _completeDraft() async {
    final signatureBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => WasteSignatureScreen(loadNumber: _currentLoad.loadNumber),
      ),
    );
    if (signatureBytes == null || !mounted) return;

    setState(() => _isSaving = true);
    String? signatureUrl;
    try {
      final online = await ConnectivityService().isOnline().catchError((_) => false);
      if (!online) {
        await WasteService().queueOfflineWasteSignatureBytes(
          signatureBytes: signatureBytes,
          loadId: _currentLoad.id!,
        );
        await SyncService().addToQueue(
          collection: Collections.wasteLoads,
          operation: 'update',
          data: {
            'status': 'completed',
            'completed_by': currentEmployee?.clockNo ?? 'unknown',
            'completed_at': DateTime.now().toIso8601String(),
          },
          documentId: _currentLoad.id!,
        );
        await SyncService().processNow();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Queued offline — will upload on reconnect'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      signatureUrl = await WasteService().uploadSignature(
        signatureBytes: signatureBytes,
        loadId: _currentLoad.id!,
      );
      await WasteService().markLoadComplete(
        _currentLoad.id!,
        driverSignatureUrl: signatureUrl,
        completedBy: currentEmployee?.clockNo ?? 'unknown',
      );
      setState(() {
        _currentLoad = _currentLoad.copyWith(
          status: WasteLoadStatus.completed,
          driverSignatureUrl: signatureUrl,
          completedBy: currentEmployee?.clockNo,
          completedAt: DateTime.now(),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Load marked complete'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      await SyncService().addToQueue(
        collection: Collections.wasteLoads,
        operation: 'update',
        data: {
          'status': 'completed',
          if (signatureUrl != null) 'driver_signature_url': signatureUrl,
          'completed_by': currentEmployee?.clockNo ?? 'unknown',
          'completed_at': DateTime.now().toIso8601String(),
        },
        documentId: _currentLoad.id!,
      );
      await SyncService().processNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Queued for retry: $e'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label  ', style: TextStyle(color: Theme.of(context).appColors.textMuted, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
      ],
    );
  }

  Widget _weightBox(String label, String value, Color color) {
    final isGrey = color == Colors.grey;
    final valueColor = isGrey ? Theme.of(context).colorScheme.onSurface : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isGrey ? Colors.grey.shade100 : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isGrey ? Colors.grey.shade400 : color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  IconData _statusIcon(WasteLoadStatus s) {
    switch (s) {
      case WasteLoadStatus.completed:          return Icons.check_circle;
      case WasteLoadStatus.scheduled:          return Icons.event_available;
      case WasteLoadStatus.pendingWeighbridge: return Icons.scale;
      case WasteLoadStatus.cancelled:          return Icons.cancel;
      default:                                 return Icons.hourglass_bottom;
    }
  }

  Color _statusColor(WasteLoadStatus s) {
    switch (s) {
      case WasteLoadStatus.completed:          return Colors.green;
      case WasteLoadStatus.scheduled:          return Colors.blue;
      case WasteLoadStatus.pendingWeighbridge: return Colors.amber.shade700;
      case WasteLoadStatus.cancelled:          return Theme.of(context).colorScheme.onSurfaceVariant;
      default:                                 return Colors.orange;
    }
  }
}

// ---------------------------------------------------------------------------
// Per-item row with inline delete button
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.canDelete,
    required this.canRemovePhotos,
    required this.onDelete,
    required this.onRemovePhoto,
  });

  final WasteItem item;
  final bool canDelete;
  final bool canRemovePhotos;
  final VoidCallback onDelete;
  final void Function(String photoUrl) onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final remotePhotos = item.photos
        .where((p) => p.startsWith('http://') || p.startsWith('https://'))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.delete_outline, size: 16, color: Theme.of(context).appColors.wasteGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.subtype,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                        if (item.sourceStockId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).appColors.wasteGreenSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).appColors.wasteGreen),
                            ),
                            child: Text('Stock',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).appColors.wasteGreen,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    Text(
                      '${item.weightKg.toStringAsFixed(1)} kg'
                      '${item.quantity != null ? '  •  Qty ${item.quantity}' : ''}'
                      '${item.photos.isNotEmpty ? '  •  ${item.photos.length} photo(s)' : ''}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'Delete item',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onDelete,
                ),
            ],
          ),
          if (remotePhotos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: remotePhotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = remotePhotos[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image, size: 20),
                          ),
                        ),
                      ),
                      if (canRemovePhotos)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => onRemovePhoto(url),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add item bottom sheet (used from load detail for post-submission additions)
// ---------------------------------------------------------------------------

class _NewItemResult {
  final String subtype;
  final double weightKg;
  final int? quantity;
  final String? notes;
  final List<String> localPhotoPaths;

  const _NewItemResult({
    required this.subtype,
    required this.weightKg,
    this.quantity,
    this.notes,
    required this.localPhotoPaths,
  });
}

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet({required this.typeNames, this.defaultType});
  final List<String> typeNames;
  final String? defaultType;

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final WasteService _wasteService = WasteService();
  late String? _type;
  final _weightCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    _type = widget.typeNames.contains(widget.defaultType)
        ? widget.defaultType
        : (widget.typeNames.isNotEmpty ? widget.typeNames.first : null);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _type != null &&
      (double.tryParse(_weightCtrl.text) ?? 0) > 0 &&
      _photos.isNotEmpty;

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _addingPhoto = true);
    try {
      final path = await _wasteService.pickAndCompressPhotoFromSource(source);
      if (path != null && mounted) setState(() => _photos.add(path));
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Text('Add Item to Load',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.typeNames.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Waste Type', isDense: true),
                  items: widget.typeNames
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v),
                )
              else
                TextField(
                  decoration: const InputDecoration(labelText: 'Waste Type *', isDense: true),
                  onChanged: (v) => setState(() => _type = v.isEmpty ? null : v),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg) *', isDense: true, suffixText: 'kg'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity (optional)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (optional)', isDense: true),
              ),
              const SizedBox(height: 12),
              Text('Photos * (${_photos.length})',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF616161))),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: _addingPhoto ? null : () => _addPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    tooltip: 'Camera',
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _addingPhoto ? null : () => _addPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    tooltip: 'Gallery',
                  ),
                  if (_addingPhoto) ...[
                    const SizedBox(width: 12),
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(File(_photos[i]), width: 60, height: 60, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0, right: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _valid
                      ? () => Navigator.pop(context, _NewItemResult(
                          subtype: _type!,
                          weightKg: double.parse(_weightCtrl.text),
                          quantity: _qtyCtrl.text.isNotEmpty ? int.tryParse(_qtyCtrl.text) : null,
                          notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
                          localPhotoPaths: List.of(_photos),
                        ))
                      : null,
                  child: const Text('Add'),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status stepper
// ---------------------------------------------------------------------------

class _WasteStatusStepper extends StatelessWidget {
  const _WasteStatusStepper({required this.status});
  final WasteLoadStatus status;

  @override
  Widget build(BuildContext context) {
    final steps = status == WasteLoadStatus.scheduled
        ? ['Scheduled', 'Collecting', 'Weighbridge', 'Complete']
        : ['Created', 'Signature', 'Weighbridge', 'Complete'];
    final currentIdx = switch (status) {
      WasteLoadStatus.scheduled          => 0,
      WasteLoadStatus.draft              => 1,
      WasteLoadStatus.pendingWeighbridge => 2,
      WasteLoadStatus.completed          => 3,
      WasteLoadStatus.cancelled          => -1,
    };
    if (status == WasteLoadStatus.cancelled) {
      final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel, size: 16, color: mutedColor),
            const SizedBox(width: 8),
            Text('Cancelled', style: TextStyle(color: mutedColor, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return Row(
      children: List.generate(steps.length, (i) {
        final done = i < currentIdx;
        final active = i == currentIdx;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? Theme.of(context).appColors.wasteGreen
                            : active ? Colors.orange
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: active ? Border.all(color: Colors.orange, width: 2) : null,
                      ),
                      child: Icon(
                        done ? Icons.check : Icons.circle,
                        size: done ? 16 : 8,
                        color: done ? Colors.white : active ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active ? Colors.orange
                            : done ? Theme.of(context).appColors.wasteGreen
                            : Theme.of(context).appColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: done ? Theme.of(context).appColors.wasteGreen : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
