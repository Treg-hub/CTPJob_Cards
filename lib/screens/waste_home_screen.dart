import 'dart:async';

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
import 'waste_pallet_inventory_screen.dart';
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

    final appColors = Theme.of(context).appColors;
    final cardBg = isToday || isPast ? appColors.wasteGreenSurface : Theme.of(context).cardColor;
    final onCardColor = isToday || isPast ? onColor(appColors.wasteGreenSurface) : Theme.of(context).colorScheme.onSurface;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: appColors.wasteGreen, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping, color: appColors.wasteGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    load.mainWasteType,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: onCardColor),
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
            Text(
              'Contractor: ${load.contractorName?.isNotEmpty == true ? load.contractorName! : load.contractorId}',
              style: TextStyle(fontSize: 13, color: onCardColor),
            ),
            if (load.scheduledNotes != null && load.scheduledNotes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Note: ${load.scheduledNotes}',
                    style: TextStyle(fontSize: 12, color: onCardColor)),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 14,
                    color: isPast ? Colors.red : appColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${isToday ? 'Today' : isPast ? 'Overdue' : 'Expected'} — '
                  '${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year} '
                  '${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPast ? Colors.red.shade700 : onCardColor,
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
                style: FilledButton.styleFrom(backgroundColor: appColors.wasteGreen),
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

class _WasteHomeScreenState extends ConsumerState<WasteHomeScreen>
    with TickerProviderStateMixin {
  final WasteService _wasteService = WasteService();
  List<WasteLoad> _recentLoads = [];
  List<WasteLoad> _scheduledLoads = [];
  bool _isLoading = true;
  String _filter = 'all'; // all | today | week

  StreamSubscription<List<WasteLoad>>? _loadsSubscription;
  StreamSubscription<List<WasteLoad>>? _scheduledSubscription;

  // Phase 7: enhanced flag state
  bool _effectiveWasteEnabled = true;
  bool _pilotModeActive = false;
  String? _userClock;

  // ── Tab controller + pending weighbridge badge counter ──
  late TabController _tabController;
  int _pendingWeighbridgeCount = 0;
  StreamSubscription<List<WasteLoad>>? _pendingCountSub;

  int _tabCount() {
    final isAdmin   = role_utils.isWasteAdmin(currentEmployee);
    final isManager = role_utils.isSecurityManager(currentEmployee);
    return 1 + (isAdmin || isManager ? 2 : 0) + (isAdmin ? 1 : 0);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount(), vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _loadFeatureStatus();
    _wasteService.processOfflineWasteQueue();
    _subscribeToLoads();
    _subscribeToPendingCount();
  }

  void _subscribeToLoads() {
    _loadsSubscription?.cancel();
    _scheduledSubscription?.cancel();

    setState(() => _isLoading = true);

    _loadsSubscription = _wasteService.watchLoads(limit: 20).listen(
      (loads) {
        if (mounted) {
          setState(() {
            _recentLoads = loads.where((l) =>
              l.status != WasteLoadStatus.scheduled &&
              l.status != WasteLoadStatus.cancelled
            ).toList();
            _isLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );

    try {
      _scheduledSubscription = _wasteService.watchScheduledLoads().listen(
        (loads) {
          if (mounted) {
            setState(() => _scheduledLoads = loads);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _scheduledLoads = []);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _scheduledLoads = []);
    }
  }

  void _subscribeToPendingCount() {
    final isAdmin   = role_utils.isWasteAdmin(currentEmployee);
    final isManager = role_utils.isSecurityManager(currentEmployee);
    if (!isAdmin && !isManager) return;
    _pendingCountSub = _wasteService.watchPendingWeighbridge().listen(
      (loads) { if (mounted) setState(() => _pendingWeighbridgeCount = loads.length); },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pendingCountSub?.cancel();
    _loadsSubscription?.cancel();
    _scheduledSubscription?.cancel();
    super.dispose();
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
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).appColors.wasteGreen,
                child: const Icon(Icons.event_available, color: Colors.white),
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
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).appColors.wasteGreen,
                child: const Icon(Icons.layers, color: Colors.white),
              ),
              title: const Text('Paper Waste Stock'),
              subtitle: const Text('View or record pallets accumulating on site'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WastePalletInventoryScreen()));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
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

  Color _statusColor(WasteLoadStatus s, BuildContext context) {
    switch (s) {
      case WasteLoadStatus.completed:          return Colors.green;
      case WasteLoadStatus.scheduled:          return Theme.of(context).appColors.wasteGreen;
      case WasteLoadStatus.pendingWeighbridge: return Colors.amber.shade700;
      case WasteLoadStatus.cancelled:          return Theme.of(context).colorScheme.onSurfaceVariant;
      default:                                 return Colors.orange;
    }
  }

  // ── Loads tab body (the original main content) ────────────────────────────
  Widget _buildLoadsTab(BuildContext context, bool isAdmin, bool isManager) {
    return Column(
      children: [
        // Offline sync banner
        if (SyncService().getQueuedWasteOperationCount() > 0)
          InkWell(
            onTap: () async => _handleRetrySync(context),
            child: Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${SyncService().getQueuedWasteOperationCount()} item(s) queued offline — tap to retry',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Paper Waste Stock summary banner
        if (role_utils.isWasteUser(currentEmployee))
          _PaperWasteStockBanner(wasteService: _wasteService),

        // Quick filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
              : ListView(
                  children: [
                    // ── Incoming (scheduled) ──────────────────────────────────
                    ...() {
                      final filteredScheduled = _scheduledLoads.where((load) {
                        final date = load.scheduledFor ?? load.dateTime;
                        if (_filter == 'today') return DateUtils.isSameDay(date, DateTime.now());
                        if (_filter == 'week') return date.isAfter(DateTime.now().subtract(const Duration(days: 7)));
                        return true;
                      }).toList();
                      if (filteredScheduled.isEmpty) return <Widget>[];
                      return <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Icon(Icons.local_shipping, color: Theme.of(context).appColors.wasteGreen, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Incoming (${filteredScheduled.length})',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).appColors.wasteGreen),
                              ),
                            ],
                          ),
                        ),
                        ...filteredScheduled.map((load) => _IncomingLoadCard(
                          load: load,
                          isManager: isManager || isAdmin,
                          wasteService: _wasteService,
                          onRefresh: _subscribeToLoads,
                        )),
                        const Divider(height: 24, indent: 16, endIndent: 16),
                      ];
                    }(),

                    // ── Recent loads ──────────────────────────────────────────
                    ...() {
                      final filtered = _recentLoads.where((load) {
                        if (_filter == 'today') return DateUtils.isSameDay(load.dateTime, DateTime.now());
                        if (_filter == 'week') return load.dateTime.isAfter(DateTime.now().subtract(const Duration(days: 7)));
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  Text(
                                    _filter == 'all'
                                        ? 'No waste loads yet.\nTap + New / Schedule to get started.'
                                        : 'No loads match "${_filter == "today" ? "Today" : "This Week"}".',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Theme.of(context).appColors.textMuted),
                                  ),
                                  if (_filter != 'all') ...[
                                    const SizedBox(height: 12),
                                    TextButton(onPressed: () => setState(() => _filter = 'all'), child: const Text('Clear filter')),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ];
                      }
                      return filtered.map((load) {
                        final statusColor = _statusColor(load.status, context);
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: load)));
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), shape: BoxShape.circle),
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
                                          '${load.mainWasteType}${load.driverName.isNotEmpty ? '  •  ${load.driverName}' : ''}',
                                          style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(formatSADate(load.dateTime), style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted)),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
                                        child: Text(
                                          load.status.displayLabel,
                                          style: TextStyle(fontSize: 11, color: onColor(statusColor), fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList();
                    }(),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _handleRetrySync(BuildContext context) async {
    final before = SyncService().getQueuedWasteOperationCount();
    setState(() => _isLoading = true);
    try {
      await _wasteService.processOfflineWasteQueue();
      await SyncService().processNow();
      if (mounted) {
        final after = SyncService().getQueuedWasteOperationCount();
        final processed = before - after;
        final msg = after == 0
            ? (processed > 0 ? 'All $before queued items synced.' : 'Sync complete.')
            : '$processed synced. $after remain queued.';
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: after == 0 ? Colors.green : Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retry failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = role_utils.isWasteAdmin(currentEmployee);
    final isManager = role_utils.isSecurityManager(currentEmployee);
    final wasteEnabled = _effectiveWasteEnabled;

    if (!wasteEnabled) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  _pilotModeActive ? 'WasteTrack is in pilot mode' : 'WasteTrack is currently disabled',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _pilotModeActive
                      ? 'Your clock number (${_userClock ?? 'unknown'}) is not included in the pilot list.'
                      : 'The feature flag has disabled WasteTrack (safety valve).',
                  style: TextStyle(color: Theme.of(context).appColors.textMuted),
                  textAlign: TextAlign.center,
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
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreen),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WasteAdminScreen())),
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Waste Admin'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // ── Build role-based tabs ──────────────────────────────────────────────
    final tabs = <Widget>[
      const Tab(text: 'Loads'),
      if (isAdmin || isManager)
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Weighbridge'),
              if (_pendingWeighbridgeCount > 0) ...[
                const SizedBox(width: 4),
                _WasteBadge(_pendingWeighbridgeCount),
              ],
            ],
          ),
        ),
      if (isAdmin || isManager) const Tab(text: 'Reports'),
      if (isAdmin) const Tab(text: 'Admin'),
    ];

    final tabViews = <Widget>[
      _buildLoadsTab(context, isAdmin, isManager),
      if (isAdmin || isManager) const WastePendingWeighbridgeScreen(embedded: true),
      if (isAdmin || isManager) const WasteReportsScreen(embedded: true),
      if (isAdmin) const WasteAdminScreen(embedded: true),
    ];

    // Sync controller length if role changes (rare, but guards against assert)
    if (_tabController.length != tabs.length) {
      _tabController.dispose();
      _tabController = TabController(length: tabs.length, vsync: this)
        ..addListener(() { if (mounted) setState(() {}); });
    }

    return Scaffold(
      // FAB only visible on the Loads tab
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showNewLoadMenu(context),
              icon: const Icon(Icons.add),
              label: const Text('New / Schedule'),
              backgroundColor: Theme.of(context).appColors.wasteGreen,
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: tabs,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: tabViews,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paper Waste Stock summary banner — tappable card shown in the loads tab.
// Fetches the on-site pallet count + estimated weight once (not a stream).
// ---------------------------------------------------------------------------
class _PaperWasteStockBanner extends StatefulWidget {
  const _PaperWasteStockBanner({required this.wasteService});
  final WasteService wasteService;

  @override
  State<_PaperWasteStockBanner> createState() => _PaperWasteStockBannerState();
}

class _PaperWasteStockBannerState extends State<_PaperWasteStockBanner> {
  bool _loading = true;
  bool _error = false;
  int _count = 0;
  double _totalKg = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await widget.wasteService.getPalletSummary('Paper Waste');
      if (mounted) {
        setState(() {
          _count = summary.count;
          _totalKg = summary.totalEstimatedKg;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const SizedBox.shrink();
    final appColors = Theme.of(context).appColors;
    final surfaceBg = appColors.wasteGreenSurface;
    final onSurface = onColor(surfaceBg);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WastePalletInventoryScreen()),
      ).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: appColors.wasteGreen, width: 1),
        ),
        child: _loading
            ? const Center(
                child: SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: appColors.wasteGreen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$_count pallet${_count == 1 ? '' : 's'} on site'
                      '${_totalKg > 0 ? ' · ~${formatSAWeight(_totalKg)} est.' : ''}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: onSurface),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: onSurface.withAlpha(150), size: 18),
                ],
              ),
      ),
    );
  }
}

// Small amber counter badge for the Weighbridge tab.
class _WasteBadge extends StatelessWidget {
  final int count;
  const _WasteBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(10)),
      child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
