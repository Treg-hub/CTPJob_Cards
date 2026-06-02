import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/waste_service.dart';
import '../models/contractor.dart';
import '../models/waste_item.dart';
import '../models/waste_load.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import '../main.dart' show currentEmployee;
import 'waste_load_detail_screen.dart';

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
        builder: (_) => WasteLoadFormScreen(wasteType: type),
      ),
    );
  }

  // Change 6: meaningful icon per main waste type name
  IconData _wasteTypeIcon(String mainType) {
    final t = mainType.toLowerCase();
    if (t.contains('hazard') || t.contains('chemical') || t.contains('toxic')) return Icons.dangerous;
    if (t.contains('recycl') || t.contains('plastic') || t.contains('glass')) return Icons.recycling;
    if (t.contains('cardboard') || t.contains('paper')) return Icons.inventory_2;
    if (t.contains('metal') || t.contains('scrap') || t.contains('steel') || t.contains('iron')) return Icons.hardware;
    if (t.contains('electronic') || t.contains('e-waste') || t.contains('ewaste')) return Icons.devices;
    if (t.contains('organic') || t.contains('food') || t.contains('green')) return Icons.eco;
    if (t.contains('copper')) return Icons.electric_bolt;
    return Icons.category;
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
                Icon(Icons.block, size: 64, color: Color(0xFF757575)),
                SizedBox(height: 16),
                Text('WasteTrack is currently disabled or not available in pilot for your account.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                SizedBox(height: 8),
                Text('Contact an administrator for access.', style: TextStyle(color: Color(0xFF616161))),
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
                  // Change 5: step progress indicator
                  const _WasteStepBar(currentStep: 1, totalSteps: 2, stepLabel: 'Select waste type'),
                  const Text(
                    'Step 1: Select Main Waste Type',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This choice locks the entire load. One load = one main waste type only.',
                    style: TextStyle(color: Color(0xFF616161)),
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
                                        // Change 6: meaningful icon
                                        Icon(
                                          _wasteTypeIcon(type.mainType),
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
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
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
  // Change 1: accept the full WasteType object instead of a plain string
  final WasteType wasteType;

  const WasteLoadFormScreen({super.key, required this.wasteType});

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

  bool _isLoading = false;

  List<Contractor> _contractors = [];

  // Change 1: derive subtypes from the passed WasteType
  List<String> get _availableSubtypes =>
      widget.wasteType.subtypes.isNotEmpty ? widget.wasteType.subtypes : ['Other'];

  @override
  void initState() {
    super.initState();
    _loadContractors();
  }

  Future<void> _loadContractors() async {
    try {
      final contractors = await _wasteService.watchContractors().first;
      if (mounted) setState(() => _contractors = contractors);
    } catch (_) {}
  }

  Future<void> _addItem() async {
    // Change 3: use a bottom sheet instead of a dialog
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: _AddWasteItemSheet(availableSubtypes: _availableSubtypes),
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
    if (_driverName.trim().isEmpty || _vehicleReg.trim().isEmpty || _contractorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver name, vehicle registration, and contractor are required.')),
      );
      return;
    }
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
          'main_waste_type': widget.wasteType.mainType,
          'contractor_id': _contractorId,
          'contractor_name': _contractors
              .where((c) => c.id == _contractorId)
              .map((c) => c.name)
              .firstOrNull,
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
        final loadId = result['id'] as String?;
        final loadNumber = result['load_number'] as String? ?? '';
        // Fetch the full load so we can navigate straight to signature/detail.
        WasteLoad? newLoad;
        if (loadId != null) {
          newLoad = await _wasteService.getLoad(loadId);
        }
        if (!mounted) return;
        if (newLoad != null) {
          // Replace the form screen with the detail screen so tapping back lands on type selection.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => WasteLoadDetailScreen(load: newLoad!)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Load $loadNumber saved — find it on the WasteTrack home screen.'),
              backgroundColor: Colors.green,
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
      appBar: AppBar(
        title: Text('New ${widget.wasteType.mainType} Load'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Change 5: step progress indicator at top
            const _WasteStepBar(currentStep: 2, totalSteps: 2, stepLabel: 'Load details & items'),

            // Live total (per spec)
            Card(
              color: Colors.green.shade100,
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
            DropdownButtonFormField<String?>(
              // ignore: deprecated_member_use
              value: _contractorId,
              items: _contractors.isEmpty
                  ? [const DropdownMenuItem<String?>(value: null, child: Text('Loading contractors...'))]
                  : [
                      const DropdownMenuItem<String?>(value: null, child: Text('Select contractor *')),
                      ..._contractors.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name))),
                    ],
              onChanged: _contractors.isEmpty ? null : (v) => setState(() => _contractorId = v),
              decoration: const InputDecoration(labelText: 'Contractor *'),
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
              style: TextStyle(color: Color(0xFF616161), fontSize: 12),
            ),
            const SizedBox(height: 8),

            // Items list
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
                    leading: const Icon(Icons.delete_outline, color: Color(0xFF2E7D32)),
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
              // Change 2: updated button label
              label: Text(_isLoading ? 'Saving...' : 'Create Load'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            // Change 2: updated footer hint text
            const Text(
              'After saving: capture driver signature, then enter weighbridge weight to complete.',
              style: TextStyle(fontSize: 12, color: Color(0xFF616161)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add waste item bottom sheet — converted from dialog to avoid lifecycle crash
// caused by camera intent firing mid-dialog and Flutter partially rebuilding
// the subtree.
// ---------------------------------------------------------------------------

class _AddWasteItemSheet extends StatefulWidget {
  const _AddWasteItemSheet({required this.availableSubtypes});
  final List<String> availableSubtypes;

  @override
  State<_AddWasteItemSheet> createState() => _AddWasteItemSheetState();
}

class _AddWasteItemSheetState extends State<_AddWasteItemSheet> {
  final WasteService _wasteService = WasteService();
  late String _subtype;
  final _weightCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    _subtype = widget.availableSubtypes.isNotEmpty ? widget.availableSubtypes.first : '';
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _subtype.isNotEmpty &&
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
    // Change 3: bottom sheet — no AlertDialog wrapper
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle bar
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
                value: _subtype,
                items: widget.availableSubtypes
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _subtype = v!),
                decoration: const InputDecoration(labelText: 'Subtype', isDense: true),
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
                            'subtype': _subtype,
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

// ---------------------------------------------------------------------------
// Change 5: Step progress indicator widget
// ---------------------------------------------------------------------------

class _WasteStepBar extends StatelessWidget {
  const _WasteStepBar({required this.currentStep, required this.totalSteps, required this.stepLabel});
  final int currentStep;
  final int totalSteps;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(totalSteps, (i) {
              final active = i < currentStep;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < totalSteps - 1 ? 4 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            'Step $currentStep of $totalSteps — $stepLabel',
            style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
          ),
        ],
      ),
    );
  }
}
