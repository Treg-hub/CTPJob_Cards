import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../models/waste_load.dart';
import '../utils/deviation.dart';
import '../utils/formatters.dart';
import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import 'waste_signature_screen.dart';
import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../services/connectivity_service.dart';
import '../constants/collections.dart';

/// View / edit a single Waste Load.
/// Supports weighbridge entry (Admin/Manager), deviation display, and eventual signature.
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

  // Phase 7 feature flag defense (mirrors home/create exactly, minimal)
  bool _effectiveWasteEnabled = true;
  bool _pilotModeActive = false;
  String? _userClock;

  @override
  void initState() {
    super.initState();
    _currentLoad = widget.load;
    _isAdmin = role_utils.isWasteAdmin(currentEmployee);
    _isManager = role_utils.isSecurityManager(currentEmployee);
    if (_currentLoad.actualWeighbridgeWeightKg != null) {
      _weighbridgeController.text = _currentLoad.actualWeighbridgeWeightKg!.toString();
    }
    _loadFeatureStatus();
    // Offline resilience: drain queued updates/photos when opening a load (weighbridge entry flow)
    _wasteService.processOfflineWasteQueue();
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled = await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    final pilot = await _wasteService.isPilotModeEnabled();
    if (mounted) {
      setState(() {
        _effectiveWasteEnabled = enabled;
        _pilotModeActive = pilot;
        _userClock = clock;
      });
    }
  }

  void _calculateAndShowDeviation() {
    final actual = double.tryParse(_weighbridgeController.text) ?? 0;
    if (actual <= 0) return;

    // Use real recorded when available (summed from items at load time); fallback keeps screen usable
    final recorded = _currentLoad.recordedWeightKg > 0 ? _currentLoad.recordedWeightKg : 0.0;

    final result = calculateDeviation(
      recordedWeightKg: recorded > 0 ? recorded : actual, // avoid div0 if no recorded yet
      actualWeightKg: actual,
    );

    final bool isDev = result.isDeviation;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(isDev ? Icons.warning_amber : Icons.check_circle, color: isDev ? Colors.red : Colors.green),
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
            Text('Thresholds: ${result.thresholdPercent.toStringAsFixed(0)}% or ${result.thresholdKg.toStringAsFixed(0)} kg', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (isDev)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red)),
                child: const Text(
                  '⚠️ EXCEEDS THRESHOLDS — Log in waste_audit + notify Security Manager (per spec). Admin review required.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (isDev)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Acknowledge (logs on server)', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<void> _saveWeighbridge() async {
    if (!_isAdmin && !_isManager) return;

    final weight = double.tryParse(_weighbridgeController.text);
    if (weight == null || weight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid positive weight')));
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
          const SnackBar(content: Text('Weighbridge weight saved (or queued for sync)'), backgroundColor: Colors.green),
        );

        // Auto-show deviation (spec: prominent alerts at >5% or >50kg)
        _calculateAndShowDeviation();

        // Client-side audit for deviation cases (queued for resilience; server CF also writes on pending checks)
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

  @override
  Widget build(BuildContext context) {
    final canEditWeighbridge = _isAdmin || _isManager;

    if (!_effectiveWasteEnabled) {
      return Scaffold(
        appBar: AppBar(title: Text(_currentLoad.loadNumber), backgroundColor: const Color(0xFF2E7D32)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.block, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_pilotModeActive ? 'WasteTrack is in pilot mode' : 'WasteTrack is currently disabled', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_pilotModeActive ? 'Your clock number (${_userClock ?? 'unknown'}) is not in the pilot list.' : 'Feature disabled (safety valve). Contact admin.', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              if (_isAdmin) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: () async { await _wasteService.setWasteMasterEnabled(true); await _loadFeatureStatus(); }, icon: const Icon(Icons.toggle_on), label: const Text('Re-enable (Admin)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
              ],
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentLoad.loadNumber),
        backgroundColor: const Color(0xFF2E7D32),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_currentLoad.mainWasteType, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Driver: ${_currentLoad.driverName} • ${_currentLoad.vehicleReg}'),
          const SizedBox(height: 16),

          if (canEditWeighbridge) ...[
            const Text('Weighbridge (Admin / Security Manager only)', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _weighbridgeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Actual Weighbridge Weight (kg)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveWeighbridge,
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Weighbridge Weight'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _calculateAndShowDeviation,
              child: const Text('Calculate Variance / Deviation'),
            ),
            const SizedBox(height: 24),
          ],

          const Text('Status & Actions', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('Status: ${_currentLoad.status.value}'),
          if (_currentLoad.actualWeighbridgeWeightKg != null)
            Text('Weighbridge: ${_currentLoad.actualWeighbridgeWeightKg} kg'),

          const SizedBox(height: 24),

          if (_currentLoad.status == WasteLoadStatus.draft)
            ElevatedButton.icon(
              onPressed: () async {
                final signatureBytes = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WasteSignatureScreen(loadNumber: _currentLoad.loadNumber),
                  ),
                );

                if (signatureBytes != null) {
                  String? signatureUrl;
                  try {
                    // When network unavailable, use the new offline-aware path (persist bytes + central 'waste_signatures' queue via SyncService + status queue).
                    // This ensures full signature+complete flow works offline, with processor uploading bytes + patching URL on reconnect (matches photo pattern).
                    final online = await ConnectivityService().isOnline().catchError((_) => false);
                    if (!online) {
                      await WasteService().queueOfflineWasteSignatureBytes(
                        signatureBytes: signatureBytes,
                        loadId: _currentLoad.id!,
                      );
                      // Queue the mark-complete status update (sig bytes processor will patch driver_signature_url; no url here)
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
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Queued for sync while offline (signature captured; will upload on reconnect)'), backgroundColor: Colors.orange),
                        );
                      }
                      return;
                    }

                    // Online path (original direct flow)
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
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Load marked complete with signature!'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    // Partial resilience: queue the completion status update so signature + complete can still land
                    // (uploadSignature failure path also now queues central sig bytes for full resilience)
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
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Temporary failure — queued for retry when online (check connection): $e'), backgroundColor: Colors.orange),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.draw),
              label: const Text('Mark Complete & Capture Driver Signature'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),

          if (_isAdmin)
            const Text('Admin-only: Soft delete, recovery, and full edit available in future versions.'),
        ],
      ),
    );
  }
}
