import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../services/sync_service.dart';
import '../utils/role.dart' as role_utils;
import '../services/waste_service.dart';
import '../models/waste_load.dart';
import '../utils/formatters.dart';
import 'waste_create_load_screen.dart';
import 'waste_admin_screen.dart';
import 'waste_reports_screen.dart';
import 'waste_pending_weighbridge_screen.dart';
import 'waste_load_detail_screen.dart';
import 'waste_queued_screen.dart';

/// Focused WasteTrack home screen for Security Manager / Guard + Admin.
/// This will become the default landing for those roles (per spec + user requirement).
class WasteHomeScreen extends ConsumerStatefulWidget {
  const WasteHomeScreen({super.key});

  @override
  ConsumerState<WasteHomeScreen> createState() => _WasteHomeScreenState();
}

class _WasteHomeScreenState extends ConsumerState<WasteHomeScreen> {
  final WasteService _wasteService = WasteService();
  List<WasteLoad> _recentLoads = [];
  bool _isLoading = true;
  String _filter = 'all'; // all | today | pending

  // Phase 7: enhanced flag state (master + simple pilot list of clock numbers)
  bool _effectiveWasteEnabled = true;
  bool _pilotModeActive = false;
  String? _userClock;

  // Lightweight last sync attempt for pilot UX (shown only when queued items exist)
  DateTime? _lastSyncAttempt;

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    // Process any offline queued waste data on entering the section (real resilience)
    _wasteService.processOfflineWasteQueue();
    _loadRecentLoads();
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

  Future<void> _loadRecentLoads() async {
    setState(() => _isLoading = true);
    try {
      // Attempt to sync any queued offline photos on refresh (real resilience)
      await _wasteService.processOfflineWasteQueue();

      // For now simple fetch; later convert to proper stream + provider
      final snapshot = await _wasteService
          .watchLoads(limit: 20)
          .first; // temporary

      setState(() {
        _recentLoads = snapshot;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load waste loads: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Shows a lightweight, dismissible bottom sheet with per-item breakdown of currently queued
  /// waste operations (using SyncService helper). Orange theme, minimal, reuses existing styles.
  /// Called on tap of the queued indicator cloud icon area in the AppBar title.
  /// Fresh data each time (live on open); no new widgets or core logic changes.
  void _showQueuedBreakdown(BuildContext context) {
    final breakdown = SyncService().getQueuedWasteBreakdown();
    final total = SyncService().getQueuedWasteOperationCount();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_upload, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Queued Waste Work ($total)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Items pending offline sync',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              if (breakdown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No breakdown available (queue may be processing).'),
                )
              else
                ...breakdown.entries.map((entry) {
                  final base = entry.key;
                  final c = entry.value;
                  String display = base;
                  if (c != 1) {
                    if (base == 'load/weighbridge update') {
                      display = 'load/weighbridge updates';
                    } else if (!base.endsWith('s') && !base.contains('(')) {
                      display = '${base}s';
                    }
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 6, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          '$c $display',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
              const Text(
                'Auto-syncs on reconnect. Use the orange cloud retry icon (top right) to force now.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.orange),
                  child: const Text('Dismiss'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = role_utils.isWasteAdmin(currentEmployee);
    final isManager = role_utils.isSecurityManager(currentEmployee);

    // Phase 7: use the enhanced effective flag from service (master + pilot clock list)
    final wasteEnabled = _effectiveWasteEnabled;

    if (!wasteEnabled) {
      // Improved disabled state with pilot support + clear messages + admin graceful recovery (no lockout)
      return Scaffold(
        appBar: AppBar(
          title: const Text('WasteTrack'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  _pilotModeActive
                      ? 'WasteTrack is in pilot mode'
                      : 'WasteTrack is currently disabled',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _pilotModeActive
                      ? 'Your clock number (${_userClock ?? 'unknown'}) is not included in the pilot list.'
                      : 'The feature flag has disabled WasteTrack (safety valve).',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact an administrator to adjust access or pilot configuration.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _wasteService.setWasteMasterEnabled(true);
                      await _loadFeatureStatus();
                    },
                    icon: const Icon(Icons.toggle_on),
                    label: const Text('Re-enable Master Flag (Admin)'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WasteAdminScreen()));
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Waste Admin (pilot list / full controls)'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('WasteTrack'),
            if (SyncService().getQueuedWasteOperationCount() > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: 'Queued offline items — tap for breakdown (photos, signatures, loads, etc.) or use retry icon to sync.',
                  child: GestureDetector(
                    onTap: () => _showQueuedBreakdown(context),
                    onLongPress: () => _showQueuedBreakdown(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_upload, size: 18, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text('${SyncService().getQueuedWasteOperationCount()}', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32), // green for waste/environment
        actions: [
          if (SyncService().getQueuedWasteOperationCount() > 0)
            IconButton(
              icon: const Icon(Icons.cloud_upload, color: Colors.orange),
              tooltip: 'Retry Offline Uploads — sync queued photos, signatures, weighbridge & other waste data now',
              onPressed: () async {
                final before = SyncService().getQueuedWasteOperationCount();
                setState(() {
                  _isLoading = true;
                  _lastSyncAttempt = DateTime.now();
                });
                try {
                  await _wasteService.processOfflineWasteQueue();
                  await SyncService().processNow();
                  await _loadRecentLoads();
                  if (mounted) {
                    final after = SyncService().getQueuedWasteOperationCount();
                    final processed = before - after;
                    String msg;
                    Color bg;
                    if (after == 0) {
                      msg = processed > 0
                          ? 'All $before queued items synced successfully (loads, photos, signatures, etc.).'
                          : 'Sync complete. No queued items remaining.';
                      bg = Colors.green;
                    } else if (processed > 0) {
                      msg = '$processed items synced. $after remain queued — check connection or retry from Waste home.';
                      bg = Colors.orange;
                    } else {
                      msg = 'Retry attempted. $after items still queued (check connection and try again).';
                      bg = Colors.orange;
                    }
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), backgroundColor: bg),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    final after = SyncService().getQueuedWasteOperationCount();
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Retry failed: $e. $after items remain queued. Check connection and retry from Waste home.'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          if (isAdmin)
            IconButton(
              icon: Icon(wasteEnabled ? Icons.toggle_on : Icons.toggle_off, color: wasteEnabled ? Colors.green : Colors.grey),
              tooltip: wasteEnabled ? 'Disable WasteTrack (safety valve)' : 'Enable WasteTrack',
              onPressed: () async {
                await _wasteService.setWasteMasterEnabled(!wasteEnabled);
                await _loadFeatureStatus();
              },
            ),
          if (isAdmin || isManager)
            IconButton(
              icon: const Icon(Icons.pending_actions),
              tooltip: 'Pending Weighbridge',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WastePendingWeighbridgeScreen()));
              },
            ),
          if ((isAdmin || isManager) && wasteEnabled)
            IconButton(
              icon: const Icon(Icons.assessment),
              tooltip: 'Reports',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WasteReportsScreen()));
              },
            ),
          if (isAdmin && wasteEnabled)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Waste Admin',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WasteAdminScreen()));
              },
            ),
        ],
      ),
      floatingActionButton: wasteEnabled
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WasteCreateLoadScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('New Load'),
              backgroundColor: const Color(0xFF2E7D32),
            )
          : null,
      body: Column(
        children: [
          // Quick filter chips (per spec)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _filter == 'today',
                  onSelected: (_) => setState(() => _filter = 'today'),
                ),
                ChoiceChip(
                  label: const Text('This Week'),
                  selected: _filter == 'week',
                  onSelected: (_) => setState(() => _filter = 'week'),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (_wasteService.sessionQueuedPhotoCount > 0)
                        Container(
                          width: double.infinity,
                          color: Colors.orange.shade100,
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '${_wasteService.sessionQueuedPhotoCount} photo(s) queued for upload when online. Tap retry to attempt now.',
                            style: const TextStyle(fontSize: 12, color: Colors.orange),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      // Lightweight last sync attempt indicator (pilot-friendly, only when central queue has items)
                      if (SyncService().getQueuedWasteOperationCount() > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            _lastSyncAttempt != null
                                ? 'Last sync attempt: ${formatSADateTime(_lastSyncAttempt!)}'
                                : 'Queued operations pending — tap cloud retry icon to sync',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      // NEW: Prominent but non-intrusive Queued Operations card (below banners, per spec).
                      // Tappable → opens dedicated lightweight waste_queued_screen.dart for per-item list + retry.
                      // Reuses exact same count getter (live). Updates on return via setState.
                      // Orange theme accent, minimal card, no new heavy widgets.
                      if (SyncService().getQueuedWasteOperationCount() > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Card(
                            color: Colors.orange.shade50,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.orange.shade200, width: 1),
                            ),
                            child: InkWell(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const WasteQueuedScreen()),
                                );
                                if (mounted) {
                                  setState(() {}); // refresh appbar badge, last-sync text, and this card itself
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cloud_queue, color: Colors.orange, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Queued Operations (${SyncService().getQueuedWasteOperationCount()}) — tap to view details & retry',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade800,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: Colors.orange, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      Expanded(
                        child: _recentLoads.isEmpty
                            ? const Center(
                                child: Text(
                                  'No waste loads yet.\nTap + New Load to get started.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadRecentLoads,
                                child: ListView.builder(
                                  itemCount: _recentLoads.length,
                                  itemBuilder: (context, index) {
                                    final load = _recentLoads[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      child: ListTile(
                                        leading: Icon(
                                          load.status == WasteLoadStatus.completed
                                              ? Icons.check_circle
                                              : Icons.hourglass_bottom,
                                          color: load.status == WasteLoadStatus.completed
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                        title: Text(load.loadNumber),
                                        subtitle: Text(
                                          '${load.mainWasteType} • ${load.driverName} • ${load.vehicleReg}',
                                        ),
                                        trailing: Text(
                                          formatSADate(load.dateTime),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        onTap: () async {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => WasteLoadDetailScreen(load: load),
                                            ),
                                          );
                                          if (mounted) {
                                            _loadRecentLoads(); // refresh after weighbridge entry, sync, etc.
                                          }
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
