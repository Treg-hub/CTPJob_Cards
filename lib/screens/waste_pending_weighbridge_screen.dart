import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/waste_service.dart';
import '../services/sync_service.dart';
import '../models/waste_load.dart';
import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';
import 'waste_load_detail_screen.dart';

/// Pending Weighbridge screen (Phase 3/6 hardened).
/// Real data via WasteService.watchPendingWeighbridge — streams loads in pending_weighbridge status.
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
      final data = await _wasteService
          .watchPendingWeighbridge()
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
      return const Scaffold(
        body: Center(child: Text('Access denied. Waste Admin or Security Manager only.')),
      );
    }

    if (!_effectiveWasteEnabled) {
      return Scaffold(
        appBar: WasteAppBar(title: 'Pending Weighbridge', isOnSite: currentEmployee?.isOnSite),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.block, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(_pilotModeActive ? 'WasteTrack is in pilot mode' : 'WasteTrack is currently disabled', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_pilotModeActive ? 'Your clock number (${_userClock ?? 'unknown'}) is not in the pilot list.' : 'Feature disabled by safety flag.', style: TextStyle(color: Theme.of(context).appColors.textMuted), textAlign: TextAlign.center),
              if (role_utils.isWasteAdmin(currentEmployee)) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: () async { await _wasteService.setWasteMasterEnabled(true); await _loadFeatureStatus(); _loadPending(); }, icon: const Icon(Icons.toggle_on), label: const Text('Re-enable (Admin)'), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreen)),
              ],
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: WasteAppBar(
        title: 'Pending Weighbridge',
        isOnSite: currentEmployee?.isOnSite,
        actions: [
          if (SyncService().getQueuedWasteOperationCount() > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
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
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.check_circle, size: 64, color: Theme.of(context).appColors.wasteGreen),
                              const SizedBox(height: 16),
                              const Text('No outstanding weighbridge entries.', textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              Text('Great job keeping weighbridge up to date!', style: TextStyle(color: Theme.of(context).appColors.textMuted)),
                            ]),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _pending.length,
                          itemBuilder: (context, i) {
                            final load = _pending[i];
                            final waitingSince = load.pendingWeighbridgeAt;
                            final waitDuration = waitingSince != null
                                ? DateTime.now().difference(waitingSince)
                                : null;
                            final waitLabel = waitDuration == null
                                ? ''
                                : waitDuration.inHours >= 1
                                    ? '${waitDuration.inHours}h waiting'
                                    : '${waitDuration.inMinutes}m waiting';
                            final isUrgent = waitDuration != null && waitDuration.inHours >= 2;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isUrgent ? Colors.red.shade300 : Colors.amber.shade300,
                                  width: 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: load)),
                                  );
                                  if (mounted) _loadPending();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.scale,
                                              color: isUrgent ? Colors.red : Colors.amber.shade700,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              load.loadNumber.isNotEmpty
                                                  ? '${load.loadNumber}  •  ${load.mainWasteType}'
                                                  : load.mainWasteType,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                          ),
                                          if (waitLabel.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isUrgent
                                                    ? Colors.red.shade50
                                                    : Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                    color: isUrgent
                                                        ? Colors.red.shade300
                                                        : Colors.amber.shade300),
                                              ),
                                              child: Text(
                                                waitLabel,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: isUrgent
                                                        ? Colors.red.shade700
                                                        : Colors.amber.shade800,
                                                    fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Text(
                                            load.driverName.isNotEmpty ? load.driverName : 'No driver',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(Icons.local_shipping, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Text(
                                            load.vehicleReg.isNotEmpty ? load.vehicleReg : '—',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) => WasteLoadDetailScreen(load: load)),
                                            );
                                            if (mounted) _loadPending();
                                          },
                                          icon: const Icon(Icons.scale, size: 16),
                                          label: const Text('Enter Weighbridge Weight'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Theme.of(context).appColors.wasteGreen,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
      // Admin-only: trigger the server-side pending-weighbridge check function
      floatingActionButton: role_utils.isWasteAdmin(currentEmployee)
          ? FloatingActionButton(
              mini: true,
              backgroundColor: Colors.grey.shade700,
              tooltip: 'Admin: run server-side pending check',
              onPressed: () async {
                try {
                  final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
                      .httpsCallable('checkWastePendingWeighbridge');
                  final result = await callable.call();
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Server check: ${result.data['message'] ?? result.data}'),
                      backgroundColor: Colors.green,
                    ));
                    _loadPending();
                  }
                } catch (e) {
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Check failed: $e'),
                      backgroundColor: Colors.red,
                    ));
                  }
                }
              },
              child: const Icon(Icons.rule, color: Colors.white),
            )
          : null,
    );
  }
}
