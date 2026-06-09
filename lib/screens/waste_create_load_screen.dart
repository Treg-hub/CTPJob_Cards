import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/waste_service.dart';
import '../models/contractor.dart';
import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_settings.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import '../utils/role.dart' as role_utils;
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

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    _wasteService.processOfflineWasteQueue();
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled = await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    if (mounted) {
      setState(() {
        _effectiveWasteEnabled = enabled;
        _isLoading = false;
      });
    }
  }

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

class _WasteLoadFormScreenState extends ConsumerState<WasteLoadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final WasteService _wasteService = WasteService();

  // Load-level fields
  String _driverName = '';
  String _vehicleReg = '';
  String? _paperDocumentRef;
  String? _notes;

  // Data
  List<Contractor> _contractors = [];
  List<WasteType> _wasteTypes = [];
  Contractor? _selectedContractor;
  WasteType? _selectedType;
  WasteSettings? _wasteSettings;

  // Items for this load (in-memory until save)
  final List<WasteItem> _items = [];
  double get _totalWeight => _items.fold(0.0, (sum, item) => sum + item.weightKg);

  // On-site stock (Paper Waste — same UX as Schedule Load)
  List<WasteStockItem> _onSiteStock = [];
  final List<String> _selectedStockIds = [];
  bool _showStockSection = false;
  bool _loadingStock = false;

  bool _isLoading = false;
  bool get _isPaperWaste => _selectedType?.mainType == 'Paper Waste';
  bool get _canSelectStock =>
      role_utils.isSecurityManager(currentEmployee, _wasteSettings) ||
      role_utils.isWasteAdmin(currentEmployee);

  List<WasteType> get _availableTypes {
    final c = _selectedContractor;
    if (c == null || c.wasteTypeIds.isEmpty) return _wasteTypes;
    return _wasteTypes.where((t) => c.wasteTypeIds.contains(t.id)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _wasteService.getWasteSettings().then((s) {
      if (mounted) setState(() => _wasteSettings = s);
    });
  }

  Future<void> _loadData() async {
    try {
      final contractors = await _wasteService.watchContractors().first;
      final types = await _wasteService.watchWasteTypes().first;
      if (mounted) {
        setState(() {
          _contractors = contractors;
          _wasteTypes = types;
        });
      }
    } catch (_) {}
  }

  void _resetStockSelection() {
    _showStockSection = false;
    _onSiteStock = [];
    _selectedStockIds.clear();
  }

  Future<void> _loadOnSiteStock(String wasteType) async {
    setState(() {
      _loadingStock = true;
      _onSiteStock = [];
      _selectedStockIds.clear();
    });
    try {
      final stock = await _wasteService
          .watchStockOnSite(wasteType)
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (mounted) {
        setState(() {
          _onSiteStock = stock;
          _showStockSection = true;
          _loadingStock = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _addItem() async {
    final typeNames = _availableTypes.map((t) => t.mainType).toList();
    if (typeNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a contractor first to see available waste types.')),
      );
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: _AddWasteItemSheet(availableTypes: typeNames),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items.add(WasteItem(
          loadId: 'temp',
          subtype: result['subtype'] as String,
          weightKg: result['weightKg'] as double,
          quantity: result['quantity'] as int?,
          photos: List<String>.from(result['photos'] as List),
        ));
      });
    }
  }

  Future<void> _saveLoad() async {
    if (_driverName.trim().isEmpty || _vehicleReg.trim().isEmpty || _selectedContractor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver name, vehicle registration, and contractor are required.')),
      );
      return;
    }
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a main waste type before saving.')),
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

    setState(() => _isLoading = true);

    try {
      final result = await _wasteService.saveCompleteWasteLoad(
        loadData: {
          'contractor_id': _selectedContractor!.id,
          'contractor_name': _selectedContractor!.name,
          'main_waste_type': _selectedType!.mainType,
          'driver_name': _driverName,
          'vehicle_reg': _vehicleReg,
          'paper_document_ref': _paperDocumentRef,
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
        }).toList(),
        actorClockNo: currentEmployee?.clockNo,
      );

      if (mounted) {
        final loadId = result['id'] as String?;
        final loadNumber = result['load_number'] as String? ?? '';
        final queuedOffline = result['queuedOffline'] == true;
        WasteLoad? newLoad;
        if (loadId != null && !queuedOffline) {
          if (_isPaperWaste && _selectedStockIds.isNotEmpty) {
            await _wasteService.addStockItemsToLoad(
              loadId: loadId,
              stockIds: _selectedStockIds,
            );
          }
          newLoad = await _wasteService.getLoad(loadId);
        }
        if (!mounted) return;
        if (newLoad != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: newLoad!)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                queuedOffline
                    ? 'Load saved offline — will sync when connection returns'
                    : 'Load $loadNumber saved — find it on the WasteTrack home screen.',
              ),
              backgroundColor: queuedOffline ? Colors.orange : Colors.green,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WasteAppBar(title: 'New Waste Load', isOnSite: currentEmployee?.isOnSite),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
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
              onChanged: _contractors.isEmpty
                  ? null
                  : (c) => setState(() {
                      _selectedContractor = c;
                      _selectedType = null;
                      _resetStockSelection();
                    }),
              decoration: const InputDecoration(labelText: 'Contractor *'),
            ),
            const SizedBox(height: 16),

            if (_selectedContractor != null) ...[
              const Text('Main Waste Type *',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableTypes.map((type) {
                  final selected = _selectedType?.mainType == type.mainType;
                  return ChoiceChip(
                    label: Text(type.mainType),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedType = type;
                        if (!(_canSelectStock && type.mainType == 'Paper Waste')) {
                          _resetStockSelection();
                        }
                      });
                      if (_canSelectStock && type.mainType == 'Paper Waste') {
                        _loadOnSiteStock(type.mainType);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              decoration: const InputDecoration(labelText: 'Driver Name *'),
              onChanged: (v) => _driverName = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Vehicle Registration *'),
              onChanged: (v) => _vehicleReg = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Paper Document Reference'),
              onChanged: (v) => _paperDocumentRef = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
              onChanged: (v) => _notes = v,
            ),

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
                      '${item.weightKg} kg'
                      '${item.quantity != null ? '  •  Qty ${item.quantity}' : ''}'
                      '${item.photos.isNotEmpty ? '  •  ${item.photos.length} photo(s)' : '  •  ⚠ No photo'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() => _items.remove(item)),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Waste Item (with photo)'),
            ),

            if (_showStockSection) ...[
              const SizedBox(height: 20),
              const Text('On-Site Stock (optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Tick saved stock from Paper Stock. Use “Add Waste Item” above for extra material captured on the spot (new photos).',
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
              else if (_onSiteStock.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'No stock currently on site.',
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
                    itemCount: _onSiteStock.length,
                    itemBuilder: (_, i) {
                      final item = _onSiteStock[i];
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
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
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
            ],

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

// ---------------------------------------------------------------------------
// Add waste item bottom sheet
// ---------------------------------------------------------------------------

class _AddWasteItemSheet extends StatefulWidget {
  const _AddWasteItemSheet({required this.availableTypes});
  final List<String> availableTypes;

  @override
  State<_AddWasteItemSheet> createState() => _AddWasteItemSheetState();
}

class _AddWasteItemSheetState extends State<_AddWasteItemSheet> {
  final WasteService _wasteService = WasteService();
  late String _wasteType;
  final _weightCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    _wasteType = widget.availableTypes.isNotEmpty ? widget.availableTypes.first : '';
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _wasteType.isNotEmpty &&
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
            margin: const EdgeInsets.only(bottom: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Waste Item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _wasteType,
                items: widget.availableTypes
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _wasteType = v!),
                decoration: const InputDecoration(labelText: 'Waste Type', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Weight (kg) *',
                  isDense: true,
                  suffixText: 'kg',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity (optional)', isDense: true),
              ),
              const SizedBox(height: 12),
              Text('Photos * (${_photos.length})', style: const TextStyle(fontSize: 12, color: Color(0xFF616161))),
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
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: 8),
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
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _valid
                      ? () => Navigator.pop(context, {
                            'subtype': _wasteType,
                            'weightKg': double.parse(_weightCtrl.text),
                            'quantity': _qtyCtrl.text.isNotEmpty ? int.tryParse(_qtyCtrl.text) : null,
                            'photos': List.of(_photos),
                          })
                      : null,
                  child: const Text('Add Item'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}
