import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/waste_service.dart';
import '../models/contractor.dart';
import '../models/waste_item.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import '../main.dart' show currentEmployee;

/// First step of Waste Load creation per spec:
/// 1. Select main waste type → this locks the entire load to that type.
/// 2. Then fill load-level fields + add waste items.
class WasteCreateLoadScreen extends ConsumerStatefulWidget {
  const WasteCreateLoadScreen({super.key});

  @override
  ConsumerState<WasteCreateLoadScreen> createState() => _WasteCreateLoadScreenState();
}

class _WasteCreateLoadScreenState extends ConsumerState<WasteCreateLoadScreen> {
  final WasteService _wasteService = WasteService();

  List<WasteType> _wasteTypes = [];
  WasteType? _selectedMainType;
  bool _isLoading = true;

  // Phase 7 pilot/flag support for disabled state on entry screen
  bool _effectiveWasteEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
    _wasteService.processOfflineWasteQueue();
    _loadWasteTypes();
  }

  Future<void> _loadFeatureStatus() async {
    final clock = currentEmployee?.clockNo;
    final enabled = await _wasteService.isWasteTrackEnabledForCurrentUser(clock);
    if (mounted) {
      setState(() => _effectiveWasteEnabled = enabled);
    }
  }

  Future<void> _loadWasteTypes() async {
    try {
      // In production this would be a proper provider/stream
      final types = await _wasteService.watchWasteTypes().first;
      setState(() {
        _wasteTypes = types;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load waste types: $e')),
        );
      }
    }
  }

  void _selectMainType(WasteType type) {
    setState(() {
      _selectedMainType = type;
    });

    // Per spec: once chosen, the load is locked to this main type.
    // Next step would navigate to the full load form + item builder.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WasteLoadFormScreen(mainWasteType: type.mainType),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_effectiveWasteEnabled) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create New Waste Load'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('WasteTrack is currently disabled or not available in pilot for your account.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                SizedBox(height: 8),
                Text('Contact an administrator for access.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Waste Load'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 1: Select Main Waste Type',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This choice locks the entire load. One load = one main waste type only.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: _wasteTypes.isEmpty
                        ? const Center(child: Text('No waste types configured yet.'))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _wasteTypes.length,
                            itemBuilder: (context, index) {
                              final type = _wasteTypes[index];
                              final isSelected = _selectedMainType?.mainType == type.mainType;

                              return Card(
                                elevation: isSelected ? 4 : 1,
                                color: isSelected ? Colors.green.shade50 : null,
                                child: InkWell(
                                  onTap: () => _selectMainType(type),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.delete,
                                          size: 40,
                                          color: isSelected ? Colors.green : Colors.grey[700],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          type.mainType,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (type.subtypes.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              '${type.subtypes.length} subtypes',
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                ],
              ),
            ),
    );
  }
}

/// Full load form after main waste type is locked (per spec).
/// Supports adding multiple WasteItems (with photos requirement), live total weight,
/// and eventual "Mark Complete + Signature".
class WasteLoadFormScreen extends ConsumerStatefulWidget {
  final String mainWasteType;

  const WasteLoadFormScreen({super.key, required this.mainWasteType});

  @override
  ConsumerState<WasteLoadFormScreen> createState() => _WasteLoadFormScreenState();
}

class _WasteLoadFormScreenState extends ConsumerState<WasteLoadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final WasteService _wasteService = WasteService();

  // Load level fields
  String? _contractorId;
  String _driverName = '';
  String _vehicleReg = '';
  String? _paperDocumentRef;
  String? _notes;

  // Items for this load (in-memory until save)
  final List<WasteItem> _items = [];
  double get _totalWeight => _items.fold(0.0, (sum, item) => sum + item.weightKg);

  // Temporary photos being built for the current item being added
  final List<String> _pendingItemPhotos = [];

  bool _isLoading = false; // Added for production save flow

  // Phase 7: effective flag (master + pilot) for disabled state + graceful degradation
  bool _effectiveWasteEnabled = true;
  bool _pilotModeActive = false;
  String? _userClock;

  // Mock data for now (will be replaced by real streams from WasteService)
  final List<Contractor> _mockContractors = [
    Contractor(id: 'c1', name: 'Glenpak'),
    Contractor(id: 'c2', name: 'Mondi'),
    Contractor(id: 'c3', name: 'Industrial Scrap Waste'),
    Contractor(id: 'c4', name: 'Mauser'),
  ];

  final List<String> _availableSubtypes = ['Nuggets', 'Rods', 'Reelends', 'Slab Waste', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadFeatureStatus();
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

  void _addItem() {
    String subtype = _availableSubtypes.first;
    double weight = 0;
    int? qty;
    List<String> itemPhotos = List.from(_pendingItemPhotos);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Waste Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: subtype,
                  items: _availableSubtypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => subtype = v!),
                  decoration: const InputDecoration(labelText: 'Subtype'),
                ),
                TextFormField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weight (kg) *'),
                  onChanged: (v) => weight = double.tryParse(v) ?? 0,
                ),
                TextFormField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity (optional)'),
                  onChanged: (v) => qty = int.tryParse(v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final path = await _wasteService.pickAndCompressPhotoFromSource(ImageSource.camera);
                    if (path != null) {
                      setDialogState(() => itemPhotos.add(path));
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: Text('Add Photo (${itemPhotos.length})'),
                ),
                if (itemPhotos.isNotEmpty)
                  const Text('Photo(s) ready — will upload on save', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (weight <= 0 || itemPhotos.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Weight + at least 1 photo required')));
                  return;
                }
                setState(() {
                  _items.add(WasteItem(
                    loadId: 'temp',
                    subtype: subtype,
                    weightKg: weight,
                    quantity: qty,
                    photos: itemPhotos,
                  ));
                  _pendingItemPhotos.clear();
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Item'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLoad() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one waste item before saving.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // PRODUCTION PATH - using the new orchestration method in WasteService
      final result = await _wasteService.saveCompleteWasteLoad(
        loadData: {
          'main_waste_type': widget.mainWasteType,
          'contractor_id': _contractorId,
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
          'localPhotos': item.photos, // the service will upload these
        }).toList(),
        // loadLevelPhotoPaths: [], // can add later
        actorClockNo: currentEmployee?.clockNo, // Phase 7: pass for pilot enforcement + usage log
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load ${result['load_number']} saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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
    // Phase 7: improved disabled state with clear pilot-aware messaging + graceful degradation
    if (!_effectiveWasteEnabled) {
      final isMasterOff = !(_pilotModeActive || (_userClock != null && _userClock!.isNotEmpty));
      return Scaffold(
        appBar: AppBar(
          title: Text('New ${widget.mainWasteType} Load'),
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
                  isMasterOff
                      ? 'WasteTrack is currently disabled'
                      : 'WasteTrack Pilot Mode',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  isMasterOff
                      ? 'Contact an administrator to re-enable.'
                      : 'Your clock number (${_userClock ?? 'unknown'}) is not included in the current pilot list.',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This screen is unavailable until the feature flag allows access.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('New ${widget.mainWasteType} Load'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Live total (per spec)
            Card(
              color: Colors.green.shade50,
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

            // Load level fields
            TextFormField(
              decoration: const InputDecoration(labelText: 'Driver Name *'),
              onChanged: (v) => _driverName = v,
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Vehicle Registration *'),
              onChanged: (v) => _vehicleReg = v,
            ),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _contractorId,
              items: _mockContractors
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _contractorId = v),
              decoration: const InputDecoration(labelText: 'Contractor * (mandatory)'),
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Paper Document Reference'),
              onChanged: (v) => _paperDocumentRef = v,
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
              onChanged: (v) => _notes = v,
            ),

            const SizedBox(height: 24),
            const Text('Waste Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text(
              'Each item requires at least 1 photo (enforced on save)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),

            // Items list
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No items yet. Tap + Add Item below.')),
              )
            else
              ..._items.map((item) => Card(
                    child: ListTile(
                      title: Text('${item.subtype} — ${item.weightKg} kg'),
                      subtitle: item.quantity != null ? Text('Qty: ${item.quantity}') : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => _items.remove(item)),
                      ),
                    ),
                  )),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Waste Item (with photo)'),
            ),

            // Offline resilience indicator (PR2-3) — valid collection-if inside Column children
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
              label: Text(_isLoading ? 'Saving...' : 'Save Draft Load'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Next steps in this flow: Mark Complete → Driver Signature → Weighbridge (Admin/Manager)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
