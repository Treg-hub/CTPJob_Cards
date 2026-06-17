import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/waste_service.dart';
import '../models/contractor.dart';
import '../models/waste_settings.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import '../utils/role.dart';
import '../utils/waste_stock_mapping.dart';
import '../main.dart' show currentEmployee;

/// Manager-facing screen: schedule an upcoming waste load before the truck arrives.
/// Creates a [WasteLoad] with status [scheduled] — no driver, items, or photos needed yet.
/// The guard will complete the load when the contractor arrives at the gate.
class WasteScheduleLoadScreen extends ConsumerStatefulWidget {
  const WasteScheduleLoadScreen({super.key});

  @override
  ConsumerState<WasteScheduleLoadScreen> createState() =>
      _WasteScheduleLoadScreenState();
}

class _WasteScheduleLoadScreenState
    extends ConsumerState<WasteScheduleLoadScreen> {
  final WasteService _wasteService = WasteService();
  final _notesController = TextEditingController();

  List<Contractor> _contractors = [];
  List<WasteType> _wasteTypes = [];
  Contractor? _selectedContractor;
  final Set<String> _selectedTypeIds = {};
  DateTime _scheduledFor = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  WasteSettings? _wasteSettings;

  // Stock item selection (shown when Paper Waste is selected, manager/admin only)
  List<WasteStockItem> _onSiteStock = [];
  final List<String> _selectedStockIds = [];
  bool _showStockSection = false;
  bool _loadingStock = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _wasteService.getWasteSettings().then((s) {
      if (mounted) setState(() => _wasteSettings = s);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    const timeout = Duration(seconds: 10);
    try {
      final contractors = await _wasteService
          .watchContractors()
          .first
          .timeout(timeout, onTimeout: () => []);
      final types = await _wasteService
          .watchWasteTypes()
          .first
          .timeout(timeout, onTimeout: () => []);
      if (mounted) {
        setState(() {
          _contractors = contractors;
          _wasteTypes = types;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data — check connection')),
        );
      }
    }
  }

  List<WasteType> get _availableTypes {
    final c = _selectedContractor;
    if (c == null || c.wasteTypeIds.isEmpty) return const [];
    return _wasteTypes.where((t) => c.wasteTypeIds.contains(t.id)).toList();
  }

  List<WasteType> get _selectedTypes => _availableTypes
      .where((t) => t.id != null && _selectedTypeIds.contains(t.id))
      .toList();
  bool get _usesPaperStock =>
      selectedChipsUsePaperStock(_selectedTypes, _wasteTypes);
  bool get _canAccess =>
      isWasteAdmin(currentEmployee) ||
      isSecurityManager(currentEmployee, _wasteSettings) ||
      (isSecurityGuard(currentEmployee, _wasteSettings) &&
          (_wasteSettings?.guardCanSchedule ?? false));

  bool get _canSelectStock =>
      isSecurityManager(currentEmployee, _wasteSettings) ||
      isWasteAdmin(currentEmployee);
  List<WasteStockItem> get _filteredOnSiteStock =>
      filterStockByChipSubtypes(_onSiteStock, _selectedTypes, _wasteTypes);

  bool get _isValid =>
      _selectedContractor != null && _selectedTypes.isNotEmpty;

  void _onContractorChanged(Contractor? contractor) {
    setState(() {
      _selectedContractor = contractor;
      _selectedTypeIds.clear();
      _showStockSection = false;
      _onSiteStock = [];
      _selectedStockIds.clear();
      if (contractor != null) {
        for (final type in _availableTypes) {
          if (type.id != null) _selectedTypeIds.add(type.id!);
        }
      }
    });
    _refreshStockForSelection();
  }

  void _toggleWasteType(WasteType type) {
    if (type.id == null) return;
    setState(() {
      if (_selectedTypeIds.contains(type.id)) {
        _selectedTypeIds.remove(type.id);
        _pruneStockSelection();
      } else {
        _selectedTypeIds.add(type.id!);
      }
    });
    _refreshStockForSelection();
  }

  void _pruneStockSelection() {
    final visibleIds =
        _filteredOnSiteStock.map((item) => item.id).whereType<String>().toSet();
    _selectedStockIds.removeWhere((id) => !visibleIds.contains(id));
  }

  void _refreshStockForSelection() {
    if (_canSelectStock && _usesPaperStock) {
      _loadOnSiteStock();
    } else {
      setState(() {
        _showStockSection = false;
        _onSiteStock = [];
        _selectedStockIds.clear();
      });
    }
  }

  Future<void> _pickDate() async {
    final admin = isWasteAdmin(currentEmployee);
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledFor,
      firstDate: admin ? DateTime(2020) : DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      setState(() {
        _scheduledFor = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _loadOnSiteStock() async {
    setState(() { _loadingStock = true; _onSiteStock = []; _selectedStockIds.clear(); });
    try {
      final pallets = await _wasteService
          .watchAllStockOnSite()
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (mounted) {
        setState(() {
          _onSiteStock = pallets;
          _showStockSection = true;
          _loadingStock = false;
          _pruneStockSelection();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);

    final employee = currentEmployee;
    try {
      await _wasteService.createScheduledLoad(
        contractorId: _selectedContractor!.id!,
        contractorName: _selectedContractor!.name,
        mainWasteType: resolveLoadMainWasteType(_selectedTypes, _wasteTypes),
        scheduledFor: _scheduledFor,
        scheduledBy: employee?.clockNo ?? '',
        scheduledByName: employee?.name ?? '',
        scheduledNotes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        // Store IDs on the load — stock is NOT marked loaded until the guard confirms
        selectedStockIds: List.of(_selectedStockIds),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Load scheduled — guard will be notified via the app'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule load: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_wasteSettings != null && !_canAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule Incoming Load')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Access denied. Security Manager, Admin, or an authorised Guard may schedule loads.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Incoming Load'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _isValid ? _save : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_contractors.isEmpty || _wasteTypes.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.settings_suggest, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('Setup Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      _contractors.isEmpty && _wasteTypes.isEmpty
                          ? 'No contractors or waste types have been added yet.\nAsk an admin to set these up in Waste Admin.'
                          : _contractors.isEmpty
                              ? 'No contractors have been added yet.\nAsk an admin to add them in Waste Admin.'
                              : 'No waste types have been added yet.\nAsk an admin to add them in Waste Admin.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Info banner ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(77),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withAlpha(77),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'The guard will see this load when the contractor arrives and will add driver details, items, photos and signature.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Contractor ───────────────────────────────
                  Text('Contractor *', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Contractor>(
                    initialValue: _selectedContractor,
                    hint: const Text('Select contractor'),
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _contractors.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.name),
                    )).toList(),
                    onChanged: _onContractorChanged,
                  ),

                  if (_selectedContractor != null) ...[
                  const SizedBox(height: 20),

                  // ── Waste type (contractor-linked only) ───────
                  Text('Waste Types *', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Select one or more types for this load. On-site stock is filtered to your selection.',
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

                  // ── On-site pallet selection (Paper Waste, manager only) ──
                  if (_showStockSection) ...[
                    const SizedBox(height: 20),
                    Text('On-Site Stock (optional)',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Select saved stock now. The guard can add more saved stock or fresh items when the truck arrives.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                              onTap: () => setState(() =>
                                  selected ? _selectedStockIds.remove(id) : _selectedStockIds.add(id)),
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
                                      ? Theme.of(context).colorScheme.primaryContainer.withAlpha(60)
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    // Checkbox
                                    Checkbox(
                                      value: selected,
                                      onChanged: (v) => setState(() =>
                                          v! ? _selectedStockIds.add(id) : _selectedStockIds.remove(id)),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    const SizedBox(width: 4),
                                    // Photo thumbnails (up to 3)
                                    if (item.photos.isNotEmpty) ...[
                                      SizedBox(
                                        width: item.photos.length == 1 ? 52 : (item.photos.length == 2 ? 96 : 136),
                                        height: 52,
                                        child: Stack(
                                          children: [
                                            for (int p = 0; p < item.photos.length && p < 3; p++)
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
                                                      width: 52, height: 52,
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
                                    // Text info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.subtype,
                                            style: const TextStyle(
                                                fontSize: 13, fontWeight: FontWeight.w600),
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
                                                    .onSurfaceVariant),
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
                  ],

                  ],

                  const SizedBox(height: 20),

                  // ── Expected date ────────────────────────────
                  Text('Expected Date *', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        DateFormat('EEE d MMM yyyy').format(_scheduledFor),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Notes ────────────────────────────────────
                  Text('Notes (optional)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Approx 500 kg, heavy vehicle, use rear gate',
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isValid && !_isSaving ? _save : null,
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Schedule Load'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
