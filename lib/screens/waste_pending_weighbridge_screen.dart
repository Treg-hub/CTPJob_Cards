import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../models/waste_load.dart';
import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../utils/formatters.dart';
import 'waste_load_detail_screen.dart';

/// Pending Weighbridge screen (Phase 3/6 hardened).
/// Real data via enhanced WasteService.watchPendingWeighbridge (3+ days, completed, no weighbridge).
/// Gated to Admin + Security Manager (existing role checks).
class WastePendingWeighbridgeScreen extends ConsumerStatefulWidget {
  const WastePendingWeighbridgeScreen({super.key});

  @override
  ConsumerState<WastePendingWeighbridgeScreen> createState() => _WastePendingWeighbridgeScreenState();
}

class _WastePendingWeighbridgeScreenState extends ConsumerState<WastePendingWeighbridgeScreen> {
  final WasteService _wasteService = WasteService();
  List<WasteLoad> _pending = [];
  bool _isLoading = true;
  String? _error;

  bool get _canAccess =>
      role_utils.isWasteAdmin(currentEmployee) || role_utils.isSecurityManager(currentEmployee);

  // Phase 7 flag defense + admin recovery (minimal, mirrors home)
  bool _effectiveWasteEnabled = true;
  bool _pilotModeActive = false;
  String? _userClock;

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    if (_canAccess) {
      _loadPending();
    }
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

  Future<void> _loadPending() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Drain any queued weighbridge updates / photos before loading fresh pending list
      await _wasteService.processOfflineWasteQueue();
      final data = await _wasteService.watchPendingWeighbridge(daysThreshold: 3).first;
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
      return const Scaffold(
        body: Center(child: Text('Access denied. Waste Admin or Security Manager only.')),
      );
    }

    if (!_effectiveWasteEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pending Weighbridge'), backgroundColor: const Color(0xFF2E7D32)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.block, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_pilotModeActive ? 'WasteTrack is in pilot mode' : 'WasteTrack is currently disabled', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_pilotModeActive ? 'Your clock number (${_userClock ?? 'unknown'}) is not in the pilot list.' : 'Feature disabled by safety flag.', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              if (role_utils.isWasteAdmin(currentEmployee)) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: () async { await _wasteService.setWasteMasterEnabled(true); await _loadFeatureStatus(); _loadPending(); }, icon: const Icon(Icons.toggle_on), label: const Text('Re-enable (Admin)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
              ],
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Pending Weighbridge'),
            if (SyncService().getQueuedWasteOperationCount() > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: 'Queued offline: waste loads/items, photos, signatures, weighbridge updates, audits etc.',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_upload, size: 16, color: Colors.orange),
                      const SizedBox(width: 2),
                      Text('${SyncService().getQueuedWasteOperationCount()}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPending, tooltip: 'Refresh'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text('Load error: $_error'),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadPending, child: const Text('Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPending,
                  child: _pending.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.check_circle, size: 64, color: Colors.green),
                              SizedBox(height: 16),
                              Text('No loads pending weighbridge entry (>3 days).', textAlign: TextAlign.center),
                              SizedBox(height: 8),
                              Text('Great job keeping weighbridge up to date!', style: TextStyle(color: Colors.grey)),
                            ]),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _pending.length,
                          itemBuilder: (context, i) {
                            final load = _pending[i];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                                title: Text('${load.loadNumber} • ${load.mainWasteType}'),
                                subtitle: Text(
                                  '${formatSADate(load.dateTime)} • ${load.driverName} • ${load.vehicleReg}\nCompleted ${load.completedAt != null ? formatSADate(load.completedAt!) : 'recently'}',
                                ),
                                isThreeLine: true,
                                trailing: const Text('ENTER\nWEIGHBRIDGE', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.orange)),
                                onTap: () async {
                                  // Real flow per spec: open detail (has weighbridge entry + prominent deviation alerts + offline queue resilience)
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => WasteLoadDetailScreen(load: load),
                                    ),
                                  );
                                  // Refresh list on return (in case weighbridge was entered or sync happened)
                                  if (mounted) {
                                    _loadPending();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
                .httpsCallable('checkWastePendingWeighbridge');
            final result = await callable.call();
            if (mounted) {
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Check result: ${result.data['message'] ?? result.data}'),
                  backgroundColor: Colors.green,
                ),
              );
              _loadPending(); // refresh list
            }
          } catch (e) {
            if (mounted) {
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Check failed: $e'), backgroundColor: Colors.red),
              );
            }
          }
        },
        icon: const Icon(Icons.refresh),
        label: const Text('Run Manual Check (Pilot)'),
      ),
    );
  }
}
