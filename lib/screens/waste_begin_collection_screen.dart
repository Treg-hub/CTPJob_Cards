import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/contractor.dart';
import '../models/waste_load.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';
import '../services/waste_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../utils/waste_stock_mapping.dart';
import '../widgets/waste_app_bar.dart';
import '../widgets/waste_stock_link_sheet.dart';
import 'waste_signature_screen.dart';

/// Guard-facing screen: complete a collection on a [scheduled] load.
///
/// Pre-linked stock items (from the manager's scheduling) are pre-populated and
/// can be confirmed or removed. The guard can also add fresh items.
/// Confirmed stock items are marked loaded in waste_stock on submit; all items
/// (stock + fresh) become waste_items on the load.
class WasteBeginCollectionScreen extends ConsumerStatefulWidget {
  const WasteBeginCollectionScreen({super.key, required this.load});

  final WasteLoad load;

  @override
  ConsumerState<WasteBeginCollectionScreen> createState() =>
      _WasteBeginCollectionScreenState();
}

class _WasteBeginCollectionScreenState
    extends ConsumerState<WasteBeginCollectionScreen> {
  final WasteService _wasteService = WasteService();
  final _driverCtrl = TextEditingController();
  final _regCtrl = TextEditingController();

  List<WasteType> _wasteTypes = [];
  List<Contractor> _contractors = [];

  // _ItemEntry list covers both pre-linked stock items and fresh items.
  final List<_ItemEntry> _items = [];
  bool _loadingPrelinked = false;

  Uint8List? _signatureBytes;
  String? _signatureTempPath;
  final List<String> _loadPhotoPaths = [];
  bool _addingLoadPhoto = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadWasteTypes();
    if (widget.load.selectedStockIds.isNotEmpty) {
      _loadPrelinkedStock();
    }
  }

  @override
  void dispose() {
    _driverCtrl.dispose();
    _regCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWasteTypes() async {
    try {
      final types = await _wasteService
          .watchWasteTypes()
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      final contractors = await _wasteService
          .watchContractors()
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (mounted) {
        setState(() {
          _wasteTypes = types;
          _contractors = contractors;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPrelinkedStock() async {
    setState(() => _loadingPrelinked = true);
    try {
      final items = await _wasteService
          .getStockItemsByIds(widget.load.selectedStockIds);
      if (mounted) {
        setState(() {
          for (final stock in items) {
            // Only add if on_site (not already loaded onto another load)
            if (stock.status == WasteStockStatus.onSite) {
              _items.add(_ItemEntry.fromStock(stock));
            }
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPrelinked = false);
    }
  }

  bool get _canSubmit =>
      _driverCtrl.text.trim().isNotEmpty &&
      _regCtrl.text.trim().isNotEmpty &&
      _items.isNotEmpty &&
      _items.every((i) => i.photoPaths.isNotEmpty) &&
      _loadPhotoPaths.isNotEmpty &&
      _signatureBytes != null &&
      !_isSubmitting;

  Future<void> _addLoadPhoto(ImageSource source) async {
    setState(() => _addingLoadPhoto = true);
    try {
      final path = await _wasteService.pickAndCompressPhotoFromSource(source);
      if (path != null && mounted) setState(() => _loadPhotoPaths.add(path));
    } finally {
      if (mounted) setState(() => _addingLoadPhoto = false);
    }
  }

  List<WasteType> get _contractorLinkedTypes {
    final contractor = _contractors.firstWhere(
      (c) => c.id == widget.load.contractorId,
      orElse: () => const Contractor(name: ''),
    );
    if (contractor.id == null || contractor.wasteTypeIds.isEmpty) {
      return _wasteTypes;
    }
    return _wasteTypes
        .where((t) => contractor.wasteTypeIds.contains(t.id))
        .toList();
  }

  bool get _usesPaperStock =>
      loadUsesPaperStock(widget.load.mainWasteType, _wasteTypes);

  Future<void> _addFromStock() async {
    if (!_usesPaperStock) return;
    final alreadyOnLoad =
        _items.where((i) => i.stockId != null).map((i) => i.stockId!).toSet();
    final picked = await WasteStockLinkSheet.show(
      context,
      wasteType: kPaperWasteStockParent,
      subtypeFilter:
          stockSubtypeFilterForChips(_contractorLinkedTypes, _wasteTypes),
      initialSelectedIds: alreadyOnLoad.toList(),
      title: 'Add saved stock',
      subtitle:
          'Select on-site stock to include. Pre-linked items are already listed — add any extra stock found at the gate.',
    );
    if (picked == null || !mounted) return;

    final newIds =
        picked.where((id) => !alreadyOnLoad.contains(id)).toList();
    if (newIds.isEmpty) return;

    try {
      final stocks = await _wasteService.getStockItemsByIds(newIds);
      if (!mounted) return;
      setState(() {
        for (final stock in stocks) {
          if (stock.id != null && stock.status == WasteStockStatus.onSite) {
            _items.add(_ItemEntry.fromStock(stock));
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load stock: $e')),
        );
      }
    }
  }

  Future<void> _addItem() async {
    final contractor = _contractors.firstWhere(
      (c) => c.id == widget.load.contractorId,
      orElse: () => const Contractor(name: ''),
    );
    final available = (contractor.id != null && contractor.wasteTypeIds.isNotEmpty)
        ? _wasteTypes.where((t) => contractor.wasteTypeIds.contains(t.id)).toList()
        : _wasteTypes;
    final typeNames =
        itemSubtypeOptionsForChips(available, _wasteTypes);

    final result = await showModalBottomSheet<_ItemEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: _AddItemSheet(types: typeNames),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _items.add(result));
    }
  }

  Future<void> _captureSignature() async {
    final bytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => WasteSignatureScreen(
          loadNumber: widget.load.loadNumber.isNotEmpty
              ? widget.load.loadNumber
              : widget.load.mainWasteType,
        ),
      ),
    );
    if (bytes != null && mounted) {
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      setState(() {
        _signatureBytes = bytes;
        _signatureTempPath = file.path;
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);

    try {
      // Build itemsData for submitCollection — includes both stock-sourced and fresh items
      final itemsData = _items.map((i) => {
        'subtype': i.subtype,
        'weight_kg': i.weightKg,
        'quantity': i.quantity,
        'notes': i.notes,
        'localPhotoPaths': i.photoPaths,
        if (i.stockId != null) 'source_stock_id': i.stockId,
      }).toList();

      // IDs of confirmed stock items to mark as loaded
      final confirmedStockIds = _items
          .where((i) => i.stockId != null)
          .map((i) => i.stockId!)
          .toList();

      final result = await _wasteService.submitCollection(
        loadId: widget.load.id!,
        driverName: _driverCtrl.text.trim(),
        vehicleReg: _regCtrl.text.trim(),
        collectedBy: currentEmployee?.clockNo ?? '',
        collectedByName: currentEmployee?.name,
        itemsData: itemsData,
        loadPhotoPaths: _loadPhotoPaths,
        signatureLocalPath: _signatureTempPath,
      );

      // Mark confirmed stock items as loaded now that the guard has confirmed them
      if (confirmedStockIds.isNotEmpty) {
        await _wasteService.markStockLoaded(confirmedStockIds, widget.load.id!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.queuedOffline
                  ? 'Collection saved offline — will sync when connection returns'
                  : 'Collection submitted — manager will enter weighbridge weight',
            ),
            backgroundColor: result.queuedOffline ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final isAlreadyStarted = e is StateError;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isAlreadyStarted ? 'Already Started' : 'Submission Failed'),
            content: Text(isAlreadyStarted
                ? 'This load was already started by another guard.'
                : 'Failed to submit: $e\n\nYour data has been saved offline and will sync when connectivity is restored.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduledDate = widget.load.scheduledFor ?? widget.load.dateTime;
    final appColors = Theme.of(context).appColors;
    final surfaceBg = appColors.wasteGreenSurface;
    final onSurface = onColor(surfaceBg);

    return Scaffold(
      appBar: WasteAppBar(
        title: 'Begin Collection',
        isOnSite: currentEmployee?.isOnSite,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Load header ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: appColors.wasteGreen, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: appColors.wasteGreen),
                      const SizedBox(width: 8),
                      Text(widget.load.mainWasteType,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: onSurface)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Contractor ID: ${widget.load.contractorId}',
                      style: TextStyle(fontSize: 13, color: onSurface)),
                  Text(
                    'Expected: ${DateFormat('EEE d MMM, HH:mm').format(scheduledDate)}',
                    style: TextStyle(fontSize: 13, color: onSurface),
                  ),
                  if (widget.load.scheduledByName != null)
                    Text('Scheduled by: ${widget.load.scheduledByName}',
                        style: TextStyle(fontSize: 12, color: onSurface)),
                  if (widget.load.scheduledNotes != null &&
                      widget.load.scheduledNotes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Manager note: ${widget.load.scheduledNotes}',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: onSurface),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('Driver Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            TextField(
              controller: _driverCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Driver Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: _regCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Vehicle Registration *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_shipping),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 24),

            // ── Waste items ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Waste Items (${_items.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_usesPaperStock)
                      TextButton.icon(
                        onPressed: _addFromStock,
                        icon: const Icon(Icons.layers_outlined, size: 18),
                        label: const Text('From stock'),
                      ),
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Fresh item'),
                    ),
                  ],
                ),
              ],
            ),
            if (_usesPaperStock)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Saved stock appears automatically when pre-linked. '
                  'Add more saved stock or capture fresh items with new photos.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            if (_loadingPrelinked)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),

            if (_items.isEmpty && !_loadingPrelinked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Text(
                  'At least one item with a photo is required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )
            else
              ..._items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final isStock = item.stockId != null;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: isStock
                        ? BorderSide(color: appColors.wasteGreen, width: 1.5)
                        : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(item.subtype,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (isStock) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: appColors.wasteGreenSurface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: appColors.wasteGreen),
                                      ),
                                      child: Text('Pre-loaded',
                                          style: TextStyle(fontSize: 10, color: appColors.wasteGreen, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('${item.weightKg} kg${item.quantity != null ? ' • qty ${item.quantity}' : ''}'),
                              if (item.photoPaths.isNotEmpty)
                                Text('${item.photoPaths.length} photo(s)',
                                    style: TextStyle(fontSize: 12, color: appColors.wasteGreen))
                              else
                                Text('⚠ Photo required',
                                    style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Remove item',
                          onPressed: () => _confirmRemoveItem(i, item),
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 24),

            // ── Loaded truck photos ──────────────────────────
            const Text('Loaded Truck Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Photograph the fully loaded truck before it leaves site.',
              style: TextStyle(fontSize: 12, color: appColors.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._loadPhotoPaths.map((path) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(path), width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _loadPhotoPaths.remove(path)),
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                )),
                if (_addingLoadPhoto)
                  const SizedBox(width: 72, height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else ...[
                  OutlinedButton.icon(
                    onPressed: () => _addLoadPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _addLoadPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Gallery'),
                  ),
                ],
              ],
            ),
            if (_loadPhotoPaths.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ At least one loaded-truck photo required',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),

            const SizedBox(height: 24),

            // ── Signature ────────────────────────────────────
            const Text('Driver Signature', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            if (_signatureBytes != null)
              Column(
                children: [
                  Container(
                    height: 80,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: appColors.wasteGreen),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_signatureBytes!, fit: BoxFit.contain),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _captureSignature,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Re-capture Signature'),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _captureSignature,
                  icon: const Icon(Icons.draw),
                  label: const Text('Capture Driver Signature *'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: appColors.wasteGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Collection', style: TextStyle(fontSize: 16)),
              ),
            ),

            if (!_canSubmit && !_isSubmitting)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Complete all fields, add items with photos, capture loaded-truck photos, and driver signature.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: appColors.textMuted),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveItem(int index, _ItemEntry item) async {
    final isStock = item.stockId != null;
    if (isStock) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove Pre-loaded Item?'),
          content: Text(
            'Remove "${item.subtype}" from this collection?\n\n'
            'The item will remain in on-site stock and can be included in a future load.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _items.removeAt(index));
  }
}

// ---------------------------------------------------------------------------
// Item entry model (local — not persisted until submit)
// ---------------------------------------------------------------------------

class _ItemEntry {
  final String subtype;
  final double weightKg;
  final int? quantity;
  final String? notes;
  final List<String> photoPaths;
  /// Non-null when this entry was pre-populated from a waste_stock item.
  final String? stockId;

  const _ItemEntry({
    required this.subtype,
    required this.weightKg,
    this.quantity,
    this.notes,
    required this.photoPaths,
    this.stockId,
  });

  /// Create an entry from a pre-loaded stock item.
  /// Photos are the stock item's existing URLs (stored as paths for display).
  factory _ItemEntry.fromStock(WasteStockItem stock) {
    return _ItemEntry(
      subtype: stock.subtype,
      weightKg: stock.estimatedWeightKg ?? 0.0,
      notes: stock.notes,
      photoPaths: stock.photos, // existing URLs from stock record
      stockId: stock.id,
    );
  }
}

// ---------------------------------------------------------------------------
// Add item bottom sheet (fresh items only — stock comes from pre-populated list)
// ---------------------------------------------------------------------------

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet({required this.types});
  final List<String> types;

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final WasteService _wasteService = WasteService();
  String? _wasteType;
  final _weightCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    if (widget.types.isNotEmpty) _wasteType = widget.types.first;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _wasteType != null &&
      double.tryParse(_weightCtrl.text) != null &&
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
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Add Waste Item',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.types.isNotEmpty) ...[
                const Text('Waste Type', style: TextStyle(fontSize: 12, color: Color(0xFF616161))),
                DropdownButton<String>(
                  value: _wasteType,
                  isExpanded: true,
                  items: widget.types.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _wasteType = v),
                ),
              ] else
                TextField(
                  decoration: const InputDecoration(labelText: 'Waste Type *', isDense: true),
                  onChanged: (v) => setState(() => _wasteType = v.isEmpty ? null : v),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg) *', isDense: true, suffixText: 'kg'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity (optional)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (optional)', isDense: true),
              ),
              const SizedBox(height: 12),
              Text('Photos (${_photos.length}) *',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF616161))),
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
              if (_photos.isNotEmpty)
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _valid
                      ? () => Navigator.pop(context, _ItemEntry(
                          subtype: _wasteType!,
                          weightKg: double.parse(_weightCtrl.text),
                          quantity: _qtyCtrl.text.isNotEmpty ? int.tryParse(_qtyCtrl.text) : null,
                          notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
                          photoPaths: List.of(_photos),
                        ))
                      : null,
                  child: const Text('Add'),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
