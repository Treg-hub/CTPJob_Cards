import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/waste_service.dart';
import '../utils/screen_insets.dart';
import '../utils/waste_create_load_draft.dart';
import '../utils/waste_save_messages.dart';
import '../utils/waste_stock_snapshot.dart';
import 'package:uuid/uuid.dart';
import '../models/contractor.dart';
import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_settings.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_stock_source.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import '../utils/role.dart' as role_utils;
import '../utils/waste_stock_mapping.dart';
import '../utils/waste_type_routing.dart';
import '../widgets/waste_add_item_sheet.dart';
import '../widgets/waste_stock_link_sheet.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';
import 'waste_load_detail_screen.dart';

/// Entry point for creating a new waste load.
/// Checks the WasteTrack feature flag first, then hands off to [WasteLoadFormScreen].
class WasteCreateLoadScreen extends ConsumerStatefulWidget {
  const WasteCreateLoadScreen({super.key});

  @override
  ConsumerState<WasteCreateLoadScreen> createState() => _WasteCreateLoadScreenState();
}

class _WasteCreateLoadScreenState extends ConsumerState<WasteCreateLoadScreen> {
  final WasteService _wasteService = WasteService();
  bool _isLoading = true;
  bool _effectiveWasteEnabled = true;
  WasteSettings? _wasteSettings;

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    _wasteService.processOfflineWasteQueue();
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled = await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    final settings = await _wasteService.getWasteSettings();
    if (mounted) {
      setState(() {
        _effectiveWasteEnabled = enabled;
        _wasteSettings = settings;
        _isLoading = false;
      });
    }
  }

  bool get _canAccess =>
      role_utils.isWasteUser(currentEmployee, _wasteSettings);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: WasteAppBar(title: 'New Waste Load', isOnSite: currentEmployee?.isOnSite),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_effectiveWasteEnabled) {
      return Scaffold(
        appBar: WasteAppBar(title: 'New Waste Load', isOnSite: currentEmployee?.isOnSite),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                const Text(
                  'WasteTrack is currently disabled or not available for your account.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact an administrator for access.',
                  style: TextStyle(color: Theme.of(context).appColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_wasteSettings != null && !_canAccess) {
      return Scaffold(
        appBar: WasteAppBar(title: 'New Waste Load', isOnSite: currentEmployee?.isOnSite),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Access denied. Waste module access is required to create loads.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return const WasteLoadFormScreen();
  }
}

/// Full load creation form.
/// Contractor is selected first; available waste types are filtered to those linked
/// to the selected contractor. Multiple items of different types can be added.
class WasteLoadFormScreen extends ConsumerStatefulWidget {
  const WasteLoadFormScreen({super.key});

  @override
  ConsumerState<WasteLoadFormScreen> createState() => _WasteLoadFormScreenState();
}

class _WasteLoadFormScreenState extends ConsumerState<WasteLoadFormScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final WasteService _wasteService = WasteService();

  final _driverCtrl = TextEditingController();
  final _vehicleRegCtrl = TextEditingController();
  final _trailerCtrl = TextEditingController();
  final _paperDocCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Load-level fields
  String _driverName = '';
  String _vehicleReg = '';
  String? _trailerReg;
  String? _paperDocumentRef;
  String? _notes;
  TimeOfDay _timeIn = TimeOfDay.now();
  TimeOfDay? _timeOut;
  bool _saved = false;
  String _createSubmitRef = const Uuid().v4();

  // Data
  List<Contractor> _contractors = [];
  List<WasteType> _wasteTypes = [];
  Contractor? _selectedContractor;
  final Set<String> _selectedTypeIds = {};
  WasteSettings? _wasteSettings;

  // Items for this load (in-memory until save)
  final List<WasteItem> _items = [];
  List<WasteStockItem> get _selectedStockItems => _onSiteStock
      .where((s) => s.id != null && _selectedStockIds.contains(s.id))
      .toList();

  double get _totalWeight {
    var total = sumRecordedWeightFromItems(_items);
    for (final id in _selectedStockIds) {
      WasteStockItem? live;
      for (final stock in _onSiteStock) {
        if (stock.id == id) {
          live = stock;
          break;
        }
      }
      if (live != null) {
        final w = live.estimatedWeightKg ?? 0;
        if (w > 0) total += w;
        continue;
      }
      for (final snap in _restoredStockSnapshots) {
        if (snap['id'] == id) {
          final w = WasteStockSnapshot.weightKg(snap);
          if (w > 0) total += w;
          break;
        }
      }
    }
    return total;
  }

  List<Map<String, dynamic>> _stockSnapshotsForSave() {
    final byId = <String, Map<String, dynamic>>{};
    for (final snap in _restoredStockSnapshots) {
      final id = snap['id'] as String?;
      if (id != null && id.isNotEmpty) byId[id] = snap;
    }
    for (final stock in _selectedStockItems) {
      if (stock.id != null) {
        byId[stock.id!] = WasteStockSnapshot.fromItem(stock);
      }
    }
    return _selectedStockIds
        .map((id) => byId[id])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Set<String> get _quantityOnlyTypeNames =>
      _wasteTypes.where((t) => t.isQuantityOnly).map((t) => t.mainType).toSet();

  Set<String> get _noSiteWeightTypeNames =>
      _wasteTypes.where((t) => t.noSiteWeight).map((t) => t.mainType).toSet();

  Map<String, String> get _quantityLabelByType {
    final map = <String, String>{};
    for (final t in _wasteTypes) {
      if (t.isQuantityOnly || t.noSiteWeight) {
        map[t.mainType] = t.quantityLabelFor('default');
      }
      for (final entry in t.quantityLabels.entries) {
        if (entry.key != 'default') map[entry.key] = entry.value;
      }
    }
    return map;
  }

  // On-site stock (Paper Waste — same UX as Schedule Load)
  List<WasteStockItem> _onSiteStock = [];
  final List<String> _selectedStockIds = [];
  List<Map<String, dynamic>> _restoredStockSnapshots = [];
  bool _loadingStock = false;

  bool _isLoading = false;
  List<WasteType> get _selectedTypes => _availableTypes
      .where((t) => t.id != null && _selectedTypeIds.contains(t.id))
      .toList();
  bool get _usesPaperStock =>
      selectedChipsUsePaperStock(_selectedTypes, _wasteTypes);
  // Converged with the Schedule + Begin Collection screens: any waste user
  // may pick on-site stock, not just admin/security-manager.
  bool get _canSelectStock =>
      role_utils.isWasteUser(currentEmployee, _wasteSettings);
  bool get _showStockSection => _usesPaperStock && _canSelectStock;
  List<WasteStockItem> get _filteredOnSiteStock =>
      filterStockByChipSubtypes(_onSiteStock, _selectedTypes, _wasteTypes);

  List<WasteType> get _availableTypes {
    final c = _selectedContractor;
    if (c == null || c.wasteTypeIds.isEmpty) return const [];
    return _wasteTypes.where((t) => c.wasteTypeIds.contains(t.id)).toList();
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isTimeIn}) async {
    final initial = isTimeIn ? _timeIn : (_timeOut ?? TimeOfDay.now());
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      setState(() {
        if (isTimeIn) {
          _timeIn = picked;
        } else {
          _timeOut = picked;
        }
      });
      _persistDraft();
    }
  }

  void _onContractorChanged(Contractor? contractor) {
    setState(() {
      _selectedContractor = contractor;
      _selectedTypeIds.clear();
      _resetStockSelection();
      if (contractor == null) {
        _items.clear();
        return;
      }
      final allowed = _wasteTypes
          .where((t) => contractor.wasteTypeIds.contains(t.id))
          .map((t) => t.mainType)
          .toSet();
      _items.removeWhere((item) => !allowed.contains(item.subtype));
      for (final type in _availableTypes) {
        if (type.id != null) _selectedTypeIds.add(type.id!);
      }
    });
    _refreshStockForSelection();
    _persistDraft();
  }

  void _toggleWasteType(WasteType type) {
    if (type.id == null) return;
    setState(() {
      if (_selectedTypeIds.contains(type.id)) {
        _selectedTypeIds.remove(type.id);
        _items.removeWhere((item) => item.subtype == type.mainType);
        _pruneStockSelection();
      } else {
        _selectedTypeIds.add(type.id!);
      }
    });
    _refreshStockForSelection();
    _persistDraft();
  }

  void _pruneStockSelection() {
    final visibleIds =
        _filteredOnSiteStock.map((item) => item.id).whereType<String>().toSet();
    _selectedStockIds.removeWhere((id) => !visibleIds.contains(id));
  }

  void _refreshStockForSelection() {
    if (_showStockSection) {
      _loadOnSiteStock();
    } else {
      _resetStockSelection();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driverCtrl.dispose();
    _vehicleRegCtrl.dispose();
    _trailerCtrl.dispose();
    _paperDocCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _persistDraft();
  }

  bool get _hasDraftContent => WasteCreateLoadDraft.hasContent(
        driverName: _driverName,
        vehicleReg: _vehicleReg,
        trailerReg: _trailerReg,
        paperDocumentRef: _paperDocumentRef,
        notes: _notes,
        contractorId: _selectedContractor?.id,
        selectedTypeIds: _selectedTypeIds.toList(),
        items: _items,
        selectedStockIds: _selectedStockIds,
      );

  void _syncFieldsFromControllers() {
    _driverName = _driverCtrl.text;
    _vehicleReg = _vehicleRegCtrl.text;
    _trailerReg = _trailerCtrl.text.isEmpty ? null : _trailerCtrl.text;
    _paperDocumentRef =
        _paperDocCtrl.text.isEmpty ? null : _paperDocCtrl.text;
    _notes = _notesCtrl.text.isEmpty ? null : _notesCtrl.text;
  }

  void _onFieldChanged() {
    _syncFieldsFromControllers();
    _persistDraft();
    setState(() {});
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null || !value.contains(':')) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _persistDraft() async {
    if (_saved || !_hasDraftContent) {
      await WasteCreateLoadDraft.clear(currentEmployee?.clockNo);
      return;
    }
    _syncFieldsFromControllers();
    try {
      await WasteCreateLoadDraft.save(
        clockNo: currentEmployee?.clockNo,
        payload: WasteCreateLoadDraft.toJson(
          createSubmitRef: _createSubmitRef,
          driverName: _driverName,
          vehicleReg: _vehicleReg,
          trailerReg: _trailerReg,
          paperDocumentRef: _paperDocumentRef,
          notes: _notes,
          contractorId: _selectedContractor?.id,
          selectedTypeIds: _selectedTypeIds.toList(),
          timeIn: _formatTime(_timeIn),
          timeOut: _timeOut != null ? _formatTime(_timeOut!) : null,
          items: _items,
          selectedStockIds: _selectedStockIds,
          selectedStockSnapshots: _stockSnapshotsForSave(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _restoreDraft() async {
    final draft = await WasteCreateLoadDraft.load(currentEmployee?.clockNo);
    if (draft == null || !mounted) return;

    Contractor? contractor;
    if (draft.contractorId != null) {
      for (final c in _contractors) {
        if (c.id == draft.contractorId) {
          contractor = c;
          break;
        }
      }
    }

    final timeIn = _parseTime(draft.timeIn) ?? _timeIn;
    final timeOut = _parseTime(draft.timeOut);

    if (draft.createSubmitRef.isNotEmpty) {
      _createSubmitRef = draft.createSubmitRef;
    }
    setState(() {
      _driverName = draft.driverName;
      _vehicleReg = draft.vehicleReg;
      _trailerReg = draft.trailerReg;
      _paperDocumentRef = draft.paperDocumentRef;
      _notes = draft.notes;
      _driverCtrl.text = draft.driverName;
      _vehicleRegCtrl.text = draft.vehicleReg;
      _trailerCtrl.text = draft.trailerReg ?? '';
      _paperDocCtrl.text = draft.paperDocumentRef ?? '';
      _notesCtrl.text = draft.notes ?? '';
      _selectedContractor = contractor;
      _selectedTypeIds
        ..clear()
        ..addAll(draft.selectedTypeIds);
      _timeIn = timeIn;
      _timeOut = timeOut;
      _items
        ..clear()
        ..addAll(draft.items);
      _selectedStockIds
        ..clear()
        ..addAll(draft.selectedStockIds);
      _restoredStockSnapshots = List<Map<String, dynamic>>.from(
        draft.selectedStockSnapshots,
      );
    });

    if (_showStockSection) {
      await _loadOnSiteStock();
      if (mounted) {
        setState(() {
          _selectedStockIds
            ..clear()
            ..addAll(draft.selectedStockIds);
        });
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draft restored — your in-progress load was kept'),
      ),
    );
  }

  Future<void> _discardDraft() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text(
          'This clears the saved load details and items so you can start fresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await WasteCreateLoadDraft.clear(currentEmployee?.clockNo);
    setState(() {
      _saved = false;
      _driverName = '';
      _vehicleReg = '';
      _trailerReg = null;
      _paperDocumentRef = null;
      _notes = null;
      _driverCtrl.clear();
      _vehicleRegCtrl.clear();
      _trailerCtrl.clear();
      _paperDocCtrl.clear();
      _notesCtrl.clear();
      _selectedContractor = null;
      _selectedTypeIds.clear();
      _items.clear();
      _selectedStockIds.clear();
      _timeIn = TimeOfDay.now();
      _timeOut = null;
      _resetStockSelection();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft discarded — form reset')),
    );
  }

  Future<void> _loadData() async {
    try {
      final contractors = await _wasteService.watchContractors().first;
      final types = await _wasteService.watchWasteTypes().first;
      final settings = await _wasteService.getWasteSettings();
      if (mounted) {
        setState(() {
          _contractors = contractors;
          _wasteTypes = types;
          _wasteSettings = settings;
        });
        await _restoreDraft();
      }
    } catch (_) {}
  }

  void _resetStockSelection() {
    _onSiteStock = [];
    _selectedStockIds.clear();
    _loadingStock = false;
  }

  Future<void> _loadOnSiteStock() async {
    setState(() {
      _loadingStock = true;
      _onSiteStock = [];
      _selectedStockIds.clear();
    });
    try {
      final stock = await _wasteService
          .fetchAllStockOnSiteOnce()
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (mounted) {
        setState(() {
          _onSiteStock = stock;
          _loadingStock = false;
          _pruneStockSelection();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _showAddItemOptions() async {
    if (_selectedTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one waste type chip first.'),
        ),
      );
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Add from on-site stock'),
              subtitle: Text(
                _usesPaperStock
                    ? 'Pick saved stock matching your selected types'
                    : 'Not available for the selected waste types',
              ),
              enabled: _usesPaperStock,
              onTap: _usesPaperStock
                  ? () => Navigator.pop(ctx, 'stock')
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Capture new item'),
              subtitle: const Text('Take photos and enter weight for fresh material'),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'stock') {
      await _addItemsFromStock();
    } else {
      await _addNewItem();
    }
  }

  Future<void> _addItemsFromStock() async {
    if (!guardPersonaSubmit(context)) return;
    final copper = _selectedTypes.any((t) => loadUsesCopperStock(t.mainType));
    final picked = await WasteStockLinkSheet.show(
      context,
      wasteType: copper
          ? WasteStockTypes.copperWaste
          : stockLinkParentType(
              resolveLoadMainWasteType(_selectedTypes, _wasteTypes),
            ),
      subtypeFilter: stockSubtypeFilterForChips(_selectedTypes, _wasteTypes),
      initialSelectedIds: _selectedStockIds,
      includeManagerOnlyStock: copper,
      title: copper ? 'Add copper stock' : 'Add from on-site stock',
      subtitle: copper
          ? 'Rods and Nuggets staged from Pre Press. Items already ticked stay selected.'
          : 'Select saved stock for this load. Items already ticked above stay selected.',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedStockIds
        ..clear()
        ..addAll(picked);
    });
    _persistDraft();
  }

  Future<void> _addNewItem() async {
    if (!guardPersonaSubmit(context)) return;
    final typeNames =
        itemSubtypeOptionsForChips(_selectedTypes, _wasteTypes);
    final result = await showModalBottomSheet<WasteAddItemSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: WasteAddItemSheet(
            types: typeNames,
            quantityOnlyTypeNames: _quantityOnlyTypeNames,
            noSiteWeightTypeNames: _noSiteWeightTypeNames,
            quantityLabelByType: _quantityLabelByType,
            photosRequired: _wasteSettings?.photosRequired ?? false,
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items.add(WasteItem(
          loadId: 'temp',
          subtype: result.subtype,
          weightKg: result.weightKg,
          quantity: result.quantity,
          photos: List<String>.from(result.localPhotoPaths),
          isQuantityOnly: result.isQuantityOnly,
          isNoSiteWeight: result.isNoSiteWeight,
        ));
      });
      _persistDraft();
    }
  }

  Future<void> _saveLoad() async {
    if (!guardPersonaSubmit(context)) return;
    if (_driverName.trim().isEmpty || _vehicleReg.trim().isEmpty || _selectedContractor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver name, vehicle registration, and contractor are required.')),
      );
      return;
    }
    if ((_paperDocumentRef ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paper document reference is required — number from the physical gate docket.')),
      );
      return;
    }
    if (_selectedTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one waste type before saving.'),
        ),
      );
      return;
    }
    if (_items.isEmpty && _selectedStockIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one waste item or select on-site stock.'),
        ),
      );
      return;
    }

    final photosRequired = _wasteSettings?.photosRequired ?? false;
    if (photosRequired) {
      final missingPhotos = _items.where((i) => i.photos.isEmpty).toList();
      if (missingPhotos.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Each manual item needs at least one photo.'),
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    _timeOut ??= TimeOfDay.now();
    _syncFieldsFromControllers();

    try {
      final result = await _wasteService.saveCompleteWasteLoad(
        loadData: {
          'contractor_id': _selectedContractor!.id,
          'contractor_name': _selectedContractor!.name,
          'main_waste_type':
              resolveLoadMainWasteType(_selectedTypes, _wasteTypes),
          'selected_waste_types':
              _selectedTypes.map((t) => t.mainType).toList(),
          'driver_name': _driverName,
          'vehicle_reg': _vehicleReg,
          if (_trailerReg != null && _trailerReg!.trim().isNotEmpty)
            'trailer_reg': _trailerReg!.trim(),
          'paper_document_ref': _paperDocumentRef,
          'security_name': currentEmployee?.name,
          'time_in': _formatTime(_timeIn),
          if (_timeOut != null) 'time_out': _formatTime(_timeOut!),
          'notes': _notes,
          'date_time': DateTime.now(),
        },
        itemsData: _items.map((item) => {
          'subtype': item.subtype,
          'weight_kg': item.weightKg,
          'quantity': item.quantity,
          'description': item.description,
          'notes': item.notes,
          'localPhotos': item.photos,
          'is_quantity_only': item.isQuantityOnly,
          'is_no_site_weight': item.isNoSiteWeight,
        }).toList(),
        selectedStockIds: _selectedStockIds,
        selectedStockSnapshots: _stockSnapshotsForSave(),
        actorClockNo: resolveWriteActor(currentEmployee)?.clockNo,
        createSubmitRef: _createSubmitRef,
      );

      if (mounted) {
        _saved = true;
        await WasteCreateLoadDraft.clear(currentEmployee?.clockNo);
        final loadId = result['id'] as String?;
        final loadNumber = result['load_number'] as String? ?? '';
        final queuedOps = (result['queuedOps'] as int?) ?? 0;
        if (!mounted) return;
        if (loadId != null) {
          final newLoad = WasteLoad(
            id: loadId,
            loadNumber: loadNumber,
            mainWasteType: resolveLoadMainWasteType(_selectedTypes, _wasteTypes),
            dateTime: DateTime.now(),
            contractorId: _selectedContractor!.id ?? '',
            contractorName: _selectedContractor!.name,
            driverName: _driverName,
            vehicleReg: _vehicleReg,
            trailerReg: _trailerReg,
            paperDocumentRef: _paperDocumentRef,
            securityName: currentEmployee?.name,
            timeIn: _formatTime(_timeIn),
            timeOut: _timeOut != null ? _formatTime(_timeOut!) : null,
            notes: _notes,
            status: WasteLoadStatus.draft,
            recordedWeightKg: _totalWeight,
            selectedWasteTypes: _selectedTypes.map((t) => t.mainType).toList(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(WasteSaveMessages.createLoadSaved(
                queuedOps: queuedOps,
                loadNumber: loadNumber,
              )),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: newLoad)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(WasteSaveMessages.createLoadSaved(
                queuedOps: queuedOps,
                loadNumber: loadNumber,
              )),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save load: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Widget> _buildOnSiteStockSection(BuildContext context) {
    return [
      const SizedBox(height: 20),
      Text('On-Site Stock (optional)',
          style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      Text(
        'Select saved stock now. Add fresh items with photos below if needed.',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      if (_loadingStock)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_filteredOnSiteStock.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            _onSiteStock.isEmpty
                ? 'No stock currently on site.'
                : 'No on-site stock matches the selected waste types.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        )
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _filteredOnSiteStock.length,
            itemBuilder: (_, i) {
              final item = _filteredOnSiteStock[i];
              final id = item.id!;
              final selected = _selectedStockIds.contains(id);
              return GestureDetector(
                onTap: () => setState(() => selected
                    ? _selectedStockIds.remove(id)
                    : _selectedStockIds.add(id)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withAlpha(60)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged: (v) => setState(() => v!
                            ? _selectedStockIds.add(id)
                            : _selectedStockIds.remove(id)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      if (item.photos.isNotEmpty) ...[
                        SizedBox(
                          width: item.photos.length == 1
                              ? 52
                              : (item.photos.length == 2 ? 96 : 136),
                          height: 52,
                          child: Stack(
                            children: [
                              for (int p = 0;
                                  p < item.photos.length && p < 3;
                                  p++)
                                Positioned(
                                  left: p * 44.0,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      item.photos[p],
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 52,
                                        height: 52,
                                        color: Colors.grey.shade200,
                                        child: const Icon(Icons.broken_image,
                                            size: 20, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.subtype,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (item.estimatedWeightKg != null)
                                  '~${formatSAWeight(item.estimatedWeightKg!)}',
                                formatSADate(item.createdAt),
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WasteAppBar(title: 'New Waste Load', isOnSite: currentEmployee?.isOnSite),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ScreenInsets.symmetricScroll(context),
          children: [
            // Live total
            Card(
              color: Theme.of(context).appColors.wasteGreenSurface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total so far:', style: TextStyle(fontSize: 16)),
                    Text(
                      '${formatSAWeight(_totalWeight)} — ${_items.length} items',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contractor (first — determines available types)
            DropdownButtonFormField<Contractor?>(
              // ignore: deprecated_member_use
              value: _selectedContractor,
              hint: const Text('Select contractor *'),
              isExpanded: true,
              items: _contractors.isEmpty
                  ? [const DropdownMenuItem<Contractor?>(value: null, child: Text('Loading...'))]
                  : _contractors.map((c) => DropdownMenuItem<Contractor?>(value: c, child: Text(c.name))).toList(),
              onChanged: _contractors.isEmpty ? null : _onContractorChanged,
              decoration: const InputDecoration(labelText: 'Contractor *'),
            ),
            const SizedBox(height: 16),

            if (_selectedContractor != null) ...[
              const Text('Waste Types *',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Select one or more types for this load. Stock and new items are filtered to your selection.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (_availableTypes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No waste types linked to this contractor. '
                    'Ask an admin to link types in Waste Admin.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableTypes.map((type) {
                  final selected =
                      type.id != null && _selectedTypeIds.contains(type.id);
                  return FilterChip(
                    label: Text(type.mainType),
                    selected: selected,
                    onSelected: (_) => _toggleWasteType(type),
                  );
                }).toList(),
              ),
              if (_showStockSection) ..._buildOnSiteStockSection(context),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _driverCtrl,
              decoration: const InputDecoration(labelText: 'Driver Name *'),
              onChanged: (_) => _onFieldChanged(),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vehicleRegCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Vehicle Registration *'),
              onChanged: (_) => _onFieldChanged(),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _trailerCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Trailer Registration (optional)'),
              onChanged: (_) => _onFieldChanged(),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _paperDocCtrl,
              decoration: const InputDecoration(
                labelText: 'Paper Document Reference *',
                hintText: 'Number from the physical gate docket',
              ),
              onChanged: (_) => _onFieldChanged(),
            ),
            const SizedBox(height: 8),
            if (currentEmployee?.name != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Security Officer'),
                subtitle: Text(currentEmployee!.name),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isTimeIn: true),
                    child: Text('Time in: ${_formatTime(_timeIn)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isTimeIn: false),
                    child: Text(
                      _timeOut != null
                          ? 'Time out: ${_formatTime(_timeOut!)}'
                          : 'Set time out',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
              onChanged: (_) => _onFieldChanged(),
            ),

            if (_hasDraftContent) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _discardDraft,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Discard draft & start over'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],

            const SizedBox(height: 24),
            const Text('Waste Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text(
              'Each item requires at least 1 photo (enforced on save)',
              style: TextStyle(color: Color(0xFF616161), fontSize: 12),
            ),
            const SizedBox(height: 8),

            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No items yet. Tap + Add Item below.')),
              )
            else
              ..._items.asMap().entries.map((e) {
                final item = e.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Theme.of(context).appColors.wasteGreen),
                    title: Text(item.subtype, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${itemMeasureLabel(item)}'
                      '${item.photos.isNotEmpty ? '  •  ${item.photos.length} photo(s)' : '  •  ⚠ No photo'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        setState(() => _items.remove(item));
                        _persistDraft();
                      },
                    ),
                  ),
                );
              }),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showAddItemOptions,
              icon: const Icon(Icons.add),
              label: const Text('Add Waste Item'),
            ),

            if (_items.any((i) => i.photos.any((p) => p.startsWith('/'))))
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                color: Colors.orange.shade100,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_items.where((i) => i.photos.any((p) => p.startsWith('/'))).length} item(s) have photos queued for upload when back online.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveLoad,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_isLoading ? 'Saving...' : 'Create Load'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).appColors.wasteGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'After saving: capture driver signature, then enter weighbridge weight to complete.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
