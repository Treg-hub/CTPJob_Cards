import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee;
import '../services/sync_service.dart';
import '../utils/role.dart' as role_utils;
import '../services/waste_service.dart';
import '../models/waste_load.dart';
import '../utils/formatters.dart';
import 'waste_create_load_screen.dart';
import 'waste_schedule_load_screen.dart';
import 'waste_begin_collection_screen.dart';
import 'waste_admin_screen.dart';
import 'waste_reports_screen.dart';
import 'waste_pending_weighbridge_screen.dart';
import 'waste_load_detail_screen.dart';
import 'waste_queued_screen.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Incoming load card — shown in the "Incoming" section of WasteHomeScreen.
// ---------------------------------------------------------------------------

class _IncomingLoadCard extends StatelessWidget {
  const _IncomingLoadCard({
    required this.load,
    required this.isManager,
    required this.wasteService,
    required this.onRefresh,
  });

  final WasteLoad load;
  final bool isManager;
  final WasteService wasteService;
  final VoidCallback onRefresh;

  Future<void> _showEditScheduleSheet(BuildContext context) async {
    DateTime editedDate = load.scheduledFor ?? load.dateTime;
    final notesCtrl = TextEditingController(text: load.scheduledNotes ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Scheduled Load',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Date picker
              const Text('Expected date', style: TextStyle(fontSize: 13, color: Color(0xFF616161))),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: editedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                  );
                  if (picked != null) {
                    setSheet(() {
                      editedDate = DateTime(picked.year, picked.month, picked.day,
                          editedDate.hour, editedDate.minute);
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                    '${editedDate.day}/${editedDate.month}/${editedDate.year} '
                    '${editedDate.hour.toString().padLeft(2, '0')}:${editedDate.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Text('Notes', style: TextStyle(fontSize: 13, color: Color(0xFF616161))),
              const SizedBox(height: 6),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Optional notes for the guard',
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await wasteService.updateLoad(load.id!, {
                          'scheduled_for': Timestamp.fromDate(editedDate),
                          'scheduled_notes': notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        onRefresh();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Failed to update: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheduledDate = load.scheduledFor ?? load.dateTime;
    final isToday = DateUtils.isSameDay(scheduledDate, DateTime.now());
    final isPast = scheduledDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isToday || isPast
          ? const Color(0xFFE8F5E9)
          : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2E7D32), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: Color(0xFF2E7D32), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    load.mainWasteType,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (isManager)
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'cancel') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cancel Load?'),
                            content: const Text('This load will be removed from the guard\'s list and cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Load')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await wasteService.cancelScheduledLoad(load.id!);
                            onRefresh();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e is StateError ? 'Load already in progress — cannot cancel' : 'Failed: $e')),
                              );
                            }
                          }
                        }
                      } else if (v == 'edit') {
                        if (context.mounted) await _showEditScheduleSheet(context);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit',   child: Text('Edit date & notes')),
                      PopupMenuItem(value: 'cancel', child: Text('Cancel load')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Contractor ID: ${load.contractorId}',
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (load.scheduledNotes != null && load.scheduledNotes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Note: ${load.scheduledNotes}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 14,
                    color: isPast ? Colors.red : const Color(0xFF616161)),
                const SizedBox(width: 4),
                Text(
                  '${isToday ? 'Today' : isPast ? 'Overdue' : 'Expected'} — '
                  '${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year} '
                  '${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPast ? Colors.red.shade700 : Colors.black87,
                    fontWeight: isPast ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Begin Collection'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => WasteBeginCollectionScreen(load: load)),
                  );
                  onRefresh();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  List<WasteLoad> _scheduledLoads = [];
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
    const timeout = Duration(seconds: 12);
    try {
      final loadsResult = await _wasteService
          .watchLoads(limit: 20)
          .first
          .timeout(timeout, onTimeout: () => []);

      // Gracefully handle scheduled loads even if index is still building
      List<WasteLoad> scheduledResult = [];
      try {
        scheduledResult = await _wasteService
            .watchScheduledLoads()
            .first
            .timeout(timeout, onTimeout: () => []);
      } catch (_) {
        // Index may still be building — show empty incoming section until ready
      }

      if (mounted) {
        setState(() {
          _recentLoads = loadsResult.where((l) =>
            l.status != WasteLoadStatus.scheduled &&
            l.status != WasteLoadStatus.cancelled
          ).toList();
          _scheduledLoads = scheduledResult;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load loads — check connection and retry'),
            action: SnackBarAction(label: 'Retry', onPressed: _loadRecentLoads),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showNewLoadMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('What would you like to do?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF2E7D32),
                child: Icon(Icons.event_available, color: Colors.white),
              ),
              title: const Text('Schedule Incoming Load'),
              subtitle: const Text('Arrange a collection before the truck arrives'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WasteScheduleLoadScreen()));
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueGrey,
                child: Icon(Icons.add, color: Colors.white),
              ),
              title: const Text('New Load (on the spot)'),
              subtitle: const Text('Create a load while the truck is here'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WasteCreateLoadScreen()));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
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
                style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
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
      case WasteLoadStatus.scheduled:          return const Color(0xFF2E7D32);
      case WasteLoadStatus.pendingWeighbridge: return Colors.amber.shade700;
      case WasteLoadStatus.cancelled:          return const Color(0xFF757575);
      default:                                 return Colors.orange;
    }
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
                const Icon(Icons.block, size: 64, color: Color(0xFF757575)),
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
                  style: const TextStyle(color: Color(0xFF616161)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact an administrator to adjust access or pilot configuration.',
                  style: const TextStyle(color: Color(0xFF424242), fontSize: 12),
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
              icon: Icon(wasteEnabled ? Icons.toggle_on : Icons.toggle_off, color: wasteEnabled ? Colors.green : const Color(0xFF757575)),
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
              onPressed: () => _showNewLoadMenu(context),
              icon: const Icon(Icons.add),
              label: const Text('New / Schedule'),
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
                        child: RefreshIndicator(
                          onRefresh: _loadRecentLoads,
                          child: ListView(
                            children: [
                              // ── Incoming section (scheduled loads awaiting guard) ──
                              if (_scheduledLoads.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.local_shipping, color: Color(0xFF2E7D32), size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Incoming (${_scheduledLoads.length})',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF2E7D32),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ..._scheduledLoads.map((load) => _IncomingLoadCard(
                                  load: load,
                                  isManager: isManager || isAdmin,
                                  wasteService: _wasteService,
                                  onRefresh: _loadRecentLoads,
                                )),
                                const Divider(height: 24, indent: 16, endIndent: 16),
                              ],

                              // ── Recent loads list ─────────────────────────────────
                              if (_recentLoads.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Text(
                                      'No waste loads yet.\nTap + New Load to get started.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              else
                                ..._recentLoads.where((load) {
                                  if (_filter == 'today') {
                                    return DateUtils.isSameDay(load.dateTime, DateTime.now());
                                  }
                                  if (_filter == 'week') {
                                    return load.dateTime.isAfter(DateTime.now().subtract(const Duration(days: 7)));
                                  }
                                  return true;
                                }).map((load) {
                                  final statusColor = _statusColor(load.status);
                                  return Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: load)),
                                        );
                                        if (mounted) _loadRecentLoads();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(alpha: 0.12),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(_statusIcon(load.status), color: statusColor, size: 20),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    load.loadNumber.isNotEmpty ? load.loadNumber : load.mainWasteType,
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${load.mainWasteType}'
                                                    '${load.driverName.isNotEmpty ? '  •  ${load.driverName}' : ''}',
                                                    style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(formatSADate(load.dateTime),
                                                    style: const TextStyle(fontSize: 12, color: Color(0xFF616161))),
                                                const SizedBox(height: 3),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    load.status.displayLabel,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: onColor(statusColor),
                                                        fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            ],
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
