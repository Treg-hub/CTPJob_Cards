import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../utils/presence_gating.dart';
import '../services/sync_service.dart';
import '../utils/role.dart' as role_utils;
import '../services/waste_service.dart';
import '../models/waste_settings.dart';
import '../models/waste_load.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import 'waste_create_load_screen.dart';
import 'waste_schedule_load_screen.dart';
import 'waste_begin_collection_screen.dart';
import 'waste_load_detail_screen.dart';
import 'waste_stock_inventory_screen.dart';
import 'waste_guide_screen.dart';
import 'waste_queued_screen.dart';
import '../utils/waste_stock_mapping.dart';
import '../widgets/waste_stock_link_sheet.dart';
import '../widgets/waste_copper_ready_panel.dart';
import '../models/waste_stock_source.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../utils/list_load_state.dart';

// ---------------------------------------------------------------------------
// Incoming load card — shown in the "Incoming" section of WasteHomeScreen.
// ---------------------------------------------------------------------------

class _IncomingLoadCard extends StatelessWidget {
  const _IncomingLoadCard({
    required this.load,
    required this.isManager,
    required this.wasteService,
    required this.onRefresh,
    this.wasteTypes = const [],
  });

  final WasteLoad load;
  final bool isManager;
  final WasteService wasteService;
  final VoidCallback onRefresh;
  final List<WasteType> wasteTypes;

  Future<void> _showEditScheduleSheet(BuildContext context) async {
    DateTime editedDate = load.scheduledFor ?? load.dateTime;
    final notesCtrl = TextEditingController(text: load.scheduledNotes ?? '');
    var selectedStockIds = List<String>.from(load.selectedStockIds);
    final usesPaperStock = loadUsesPaperStock(load.mainWasteType, wasteTypes);

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

              if (isManager &&
                  loadCanLinkOnSiteStock(load.mainWasteType, wasteTypes)) ...[
                const SizedBox(height: 14),
                const Text('On-site stock',
                    style: TextStyle(fontSize: 13, color: Color(0xFF616161))),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    final copper = loadUsesCopperStock(load.mainWasteType);
                    final picked = await WasteStockLinkSheet.show(
                      ctx,
                      wasteType: stockLinkParentType(load.mainWasteType),
                      subtypeFilter: stockSubtypeFilterForLoadMainType(
                        load.mainWasteType,
                        wasteTypes,
                      ),
                      initialSelectedIds: selectedStockIds,
                      includeManagerOnlyStock: copper,
                      title: copper
                          ? 'Link copper stock'
                          : 'Link on-site stock',
                      subtitle: copper
                          ? 'Rods and Nuggets staged from Pre Press for this collection.'
                          : null,
                    );
                    if (picked != null) {
                      setSheet(() => selectedStockIds = picked);
                    }
                  },
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: Text(
                    selectedStockIds.isEmpty
                        ? 'Link stock items'
                        : '${selectedStockIds.length} stock item${selectedStockIds.length == 1 ? '' : 's'} linked',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Linked items appear when the guard starts collection.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
                ),
              ],

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
                        final result = await wasteService.updateLoad(load.id!, {
                          'scheduled_for': Timestamp.fromDate(editedDate),
                          'scheduled_notes': notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
                          if (usesPaperStock && isManager)
                            'selected_stock_ids': selectedStockIds,
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (result.queuedOffline) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Saved offline — will sync when connection returns'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
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
    final usesPaperStock = loadUsesPaperStock(load.mainWasteType, wasteTypes);

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
                      PopupMenuItem(value: 'edit',   child: Text('Edit schedule & stock')),
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
            if (usesPaperStock && isManager) ...[
              const SizedBox(height: 4),
              Text(
                load.selectedStockIds.isEmpty
                    ? 'No on-site stock linked yet'
                    : '${load.selectedStockIds.length} stock item${load.selectedStockIds.length == 1 ? '' : 's'} linked for collection',
                style: TextStyle(
                  fontSize: 12,
                  color: load.selectedStockIds.isEmpty
                      ? appColors.textMuted
                      : appColors.wasteGreen,
                  fontWeight: load.selectedStockIds.isEmpty
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ],
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
            if (usesPaperStock && isManager)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.layers_outlined, size: 18),
                    label: Text(
                      load.selectedStockIds.isEmpty
                          ? 'Link on-site stock'
                          : 'Manage linked stock (${load.selectedStockIds.length})',
                    ),
                    onPressed: () async {
                      if (context.mounted) await _showEditScheduleSheet(context);
                    },
                  ),
                ),
              ),
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

class _WasteHomeScreenState extends ConsumerState<WasteHomeScreen> {
  final WasteService _wasteService = WasteService();
  List<WasteLoad> _completedLoads = [];
  List<WasteLoad> _scheduledLoads = [];
  List<WasteType> _wasteTypes = [];
  String _filter = 'all'; // all | today | week

  late final Stream<WasteLoadListSnapshot> _activeLoadsStream =
      _wasteService.watchActiveLoadsWithMeta();
  StreamSubscription<List<WasteLoad>>? _completedLoadsSubscription;
  StreamSubscription<List<WasteLoad>>? _scheduledSubscription;
  StreamSubscription<List<WasteType>>? _wasteTypesSubscription;

  bool _effectiveWasteEnabled = true;
  WasteSettings? _wasteSettings;

  @override
  void initState() {
    super.initState();
    _wasteService.processOfflineWasteQueue();
    _subscribeToLoads();
    _loadFeatureStatus();
  }

  void _subscribeToLoads() {
    _completedLoadsSubscription?.cancel();
    _scheduledSubscription?.cancel();
    _wasteTypesSubscription?.cancel();

    _wasteTypesSubscription = _wasteService.watchWasteTypes().listen(
      (types) { if (mounted) setState(() => _wasteTypes = types); },
      onError: (_) {},
    );

    _completedLoadsSubscription = _wasteService.watchRecentCompleted().listen(
      (loads) {
        if (mounted) setState(() => _completedLoads = loads);
      },
      onError: (_) { if (mounted) setState(() => _completedLoads = []); },
    );

    _scheduledSubscription = _wasteService.watchScheduledLoads().listen(
      (loads) {
        if (mounted) setState(() => _scheduledLoads = loads);
      },
      onError: (_) {
        if (mounted) setState(() => _scheduledLoads = []);
      },
    );
  }

  @override
  void dispose() {
    _completedLoadsSubscription?.cancel();
    _scheduledSubscription?.cancel();
    _wasteTypesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadFeatureStatus() async {
    final settings = await _wasteService.getWasteSettings();
    if (mounted) {
      setState(() {
        _wasteSettings = settings;
        _effectiveWasteEnabled = settings.wasteEnabled;
      });
    }
  }

  void _showNewLoadMenu(BuildContext context) {
    final isWasteUser = role_utils.isWasteUser(currentEmployee, _wasteSettings);
    final canSchedule = isWasteUser;

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
            if (canSchedule)
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
            if (isWasteUser)
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
            if (role_utils.canViewWasteStockInventory(currentEmployee, _wasteSettings))
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).appColors.wasteGreen,
                  child: const Icon(Icons.layers, color: Colors.white),
                ),
                title: const Text('On-site Stock'),
                subtitle: const Text('View or record items accumulating on site'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const WasteStockInventoryScreen()));
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
      case WasteLoadStatus.pendingCostReview: return Icons.rate_review;
      case WasteLoadStatus.cancelled:          return Icons.cancel;
      default:                                 return Icons.hourglass_bottom;
    }
  }

  Color _statusColor(WasteLoadStatus s, BuildContext context) {
    switch (s) {
      case WasteLoadStatus.completed:          return Colors.green;
      case WasteLoadStatus.scheduled:          return Theme.of(context).appColors.wasteGreen;
      case WasteLoadStatus.pendingWeighbridge: return Colors.amber.shade700;
      case WasteLoadStatus.pendingCostReview: return Colors.purple;
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WasteQueuedScreen()),
            ),
            child: Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${SyncService().getQueuedWasteOperationCount()} item(s) waiting to sync — tap to view',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: Colors.orange.shade800),
                ],
              ),
            ),
          ),

        if (role_utils.canViewCopperReadyPanel(currentEmployee, _wasteSettings))
          WasteCopperReadyPanel(wasteService: _wasteService),

        // On-site stock summary banner (managers/admins only — guards link at collection)
        if (role_utils.canViewWasteStockInventory(currentEmployee, _wasteSettings))
          _OnSiteStockBanner(wasteService: _wasteService, wasteTypes: _wasteTypes),

        // Help icon + quick filter chips in one row
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Load lifecycle guide',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WasteGuideScreen()),
                ),
                icon: const Icon(Icons.help_outline),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
              ),
              Wrap(
                spacing: 6,
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
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<WasteLoadListSnapshot>(
            stream: _activeLoadsStream,
            builder: (context, activeSnap) {
              if (activeSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 48,
                            color: Theme.of(context).appColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load waste loads',
                          style: TextStyle(
                              color: Theme.of(context).appColors.textMuted),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final meta = activeSnap.data;
              switch (decideListLoadState(
                hasSnapshot: meta != null,
                isEmpty: meta?.loads.isEmpty ?? true,
                isFromCache: meta?.isFromCache ?? true,
              )) {
                case ListLoadState.loading:
                  return const Center(child: CircularProgressIndicator());
                case ListLoadState.waitingForServer:
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          'Waiting for connection…',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                case ListLoadState.empty:
                case ListLoadState.data:
                  break;
              }

              final activeLoads = meta!.loads;

              return ListView(
                padding: EdgeInsets.only(
                  bottom: ScreenInsets.scrollBottomInHomeShell(
                    clearFab: true,
                    extendedFab: true,
                  ),
                ),
                children: [
                  // ── Incoming (scheduled) ──────────────────────────────────
                  ...() {
                    final filteredScheduled = _scheduledLoads.where((load) {
                      final date = load.scheduledFor ?? load.dateTime;
                      if (_filter == 'today') {
                        return DateUtils.isSameDay(date, DateTime.now());
                      }
                      if (_filter == 'week') {
                        return date.isAfter(
                            DateTime.now().subtract(const Duration(days: 7)));
                      }
                      return true;
                    }).toList();
                    if (filteredScheduled.isEmpty) return <Widget>[];
                    return <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping,
                                color: Theme.of(context).appColors.wasteGreen,
                                size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Incoming (${filteredScheduled.length})',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).appColors.wasteGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...filteredScheduled.map((load) => _IncomingLoadCard(
                            load: load,
                            isManager: isManager || isAdmin,
                            wasteService: _wasteService,
                            onRefresh: _subscribeToLoads,
                            wasteTypes: _wasteTypes,
                          )),
                      const Divider(height: 24, indent: 16, endIndent: 16),
                    ];
                  }(),

                  // ── Active loads (in-progress) ────────────────────────────
                  ...() {
                    final filtered = activeLoads.where((load) {
                      if (_filter == 'today') {
                        return DateUtils.isSameDay(load.dateTime, DateTime.now());
                      }
                      if (_filter == 'week') {
                        return load.dateTime.isAfter(
                            DateTime.now().subtract(const Duration(days: 7)));
                      }
                      return true;
                    }).toList();

                    if (filtered.isEmpty && _completedLoads.isEmpty) {
                      return [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 48,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(
                                  _filter == 'all'
                                      ? 'No waste loads yet.\nTap + New / Schedule to get started.'
                                      : 'No loads match "${_filter == "today" ? "Today" : "This Week"}".',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).appColors.textMuted),
                                ),
                                if (_filter != 'all') ...[
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _filter = 'all'),
                                    child: const Text('Clear filter'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ];
                    }
                    return filtered
                        .map((load) => _loadCard(load, context))
                        .toList();
                  }(),

                  // ── Recent completed (last 10) ────────────────────────────
                  ...() {
                    final filtered = _completedLoads.where((load) {
                      if (_filter == 'today') {
                        return DateUtils.isSameDay(load.dateTime, DateTime.now());
                      }
                      if (_filter == 'week') {
                        return load.dateTime.isAfter(
                            DateTime.now().subtract(const Duration(days: 7)));
                      }
                      return true;
                    }).toList();
                    if (filtered.isEmpty) return <Widget>[];
                    return <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 16,
                                color: Theme.of(context).appColors.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              'Recent completed',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).appColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...filtered.map((load) =>
                          Opacity(opacity: 0.65, child: _loadCard(load, context))),
                    ];
                  }(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _loadCard(WasteLoad load, BuildContext context) {
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
                      load.loadNumber.isNotEmpty
                          ? '${load.mainWasteType}${load.driverName.isNotEmpty ? '  •  ${load.driverName}' : ''}'
                          : load.driverName.isNotEmpty
                              ? load.driverName
                              : '',
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
  }

  @override
  Widget build(BuildContext context) {
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canUseOnSiteOnlyModules(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return const OffSiteBlockedScreen(title: 'Waste Recovery');
    }

    final isAdmin = role_utils.isWasteAdmin(currentEmployee);
    final isManager = role_utils.isSecurityManager(currentEmployee, _wasteSettings);
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
                const Text(
                  'Waste Management is disabled',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact your administrator to re-enable the module.',
                  style: TextStyle(color: Theme.of(context).appColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final updated = (_wasteSettings ?? WasteSettings.defaults)
                          .copyWith(wasteEnabled: true);
                      await _wasteService.saveWasteSettings(updated);
                      await _loadFeatureStatus();
                    },
                    icon: const Icon(Icons.toggle_on),
                    label: const Text('Re-enable (Admin)'),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appColors.wasteGreen),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewLoadMenu(context),
        icon: const Icon(Icons.add),
        label: const Text('New / Schedule'),
        backgroundColor: Theme.of(context).appColors.wasteGreen,
      ),
      body: _buildLoadsTab(context, isAdmin, isManager),
    );
  }
}

// ---------------------------------------------------------------------------
// On-site stock summary banner — tappable card shown in the loads tab.
// Separates weight-based items from quantity-only items (e.g. IBC Bins) so
// both measures are displayed accurately.
// ---------------------------------------------------------------------------
class _OnSiteStockBanner extends StatefulWidget {
  const _OnSiteStockBanner({
    required this.wasteService,
    this.wasteTypes = const [],
  });
  final WasteService wasteService;
  final List<WasteType> wasteTypes;

  @override
  State<_OnSiteStockBanner> createState() => _OnSiteStockBannerState();
}

class _OnSiteStockBannerState extends State<_OnSiteStockBanner> {
  bool _loading = true;
  bool _error = false;
  int _weightedCount = 0;
  int _qtyOnlyCount = 0;
  double _totalKg = 0;

  Set<String> get _qtyOnlyTypeNames =>
      widget.wasteTypes.where((t) => t.isQuantityOnly).map((t) => t.mainType).toSet();

  @override
  void initState() {
    super.initState();
    _loadStockOnce();
  }

  Future<void> _loadStockOnce() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final items = await widget.wasteService.fetchAllStockOnSiteOnce();
      if (!mounted) return;
      final qtyTypes = _qtyOnlyTypeNames;
      int wtCount = 0;
      int qtyCount = 0;
      double totalKg = 0;
      for (final i in items) {
        if (i.visibility == WasteStockVisibility.managerOnly) continue;
        if (qtyTypes.contains(i.wasteType) || qtyTypes.contains(i.subtype)) {
          qtyCount += i.quantity;
        } else {
          wtCount++;
          totalKg += i.estimatedWeightKg ?? 0.0;
        }
      }
      setState(() {
        _weightedCount = wtCount;
        _qtyOnlyCount = qtyCount;
        _totalKg = totalKg;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _buildSummary() {
    final total = _weightedCount + _qtyOnlyCount;
    if (total == 0) return '';
    if (_weightedCount > 0 && _qtyOnlyCount > 0) {
      final wtPart = _totalKg > 0 ? '~${formatSAWeight(_totalKg)}' : '$_weightedCount item${_weightedCount == 1 ? '' : 's'}';
      return '$wtPart  +  $_qtyOnlyCount bin${_qtyOnlyCount == 1 ? '' : 's'}';
    }
    if (_qtyOnlyCount > 0) return '$_qtyOnlyCount bin${_qtyOnlyCount == 1 ? '' : 's'} ready';
    return _totalKg > 0 ? '~${formatSAWeight(_totalKg)}' : '';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const SizedBox.shrink();
    final total = _weightedCount + _qtyOnlyCount;
    final appColors = Theme.of(context).appColors;
    final surfaceBg = appColors.wasteGreenSurface;
    final onSurface = onColor(surfaceBg);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WasteStockInventoryScreen()),
      ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$total item${total == 1 ? '' : 's'} on site',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onSurface),
                        ),
                        if (!_loading && _buildSummary().isNotEmpty)
                          Text(
                            _buildSummary(),
                            style: TextStyle(fontSize: 11, color: onSurface.withAlpha(180)),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: onSurface.withAlpha(150), size: 18),
                ],
              ),
      ),
    );
  }
}


