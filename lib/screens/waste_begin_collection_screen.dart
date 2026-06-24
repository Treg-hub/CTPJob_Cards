import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/contractor.dart';
import '../models/waste_settings.dart';
import '../models/waste_load.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_type.dart';
import '../services/waste_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../models/waste_stock_source.dart';
import '../utils/waste_stock_mapping.dart';
import '../utils/waste_type_routing.dart';
import '../widgets/waste_add_item_sheet.dart';
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
  late final TextEditingController _paperDocCtrl;
  TimeOfDay _timeIn = TimeOfDay.now();
  TimeOfDay? _timeOut;

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
  WasteSettings? _wasteSettings;

  bool get _photosRequired => _wasteSettings?.photosRequired ?? false;
  bool get _signatureRequired => _wasteSettings?.signatureRequired ?? false;

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
    }
  }

  @override
  void initState() {
    super.initState();
    _paperDocCtrl = TextEditingController(text: widget.load.paperDocumentRef ?? '');
    _loadWasteSettings();
    _loadWasteTypes();
    if (widget.load.selectedStockIds.isNotEmpty) {
      _loadPrelinkedStock();
    }
  }

  @override
  void dispose() {
    _driverCtrl.dispose();
    _regCtrl.dispose();
    _paperDocCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWasteSettings() async {
    try {
      final settings = await _wasteService.getWasteSettings();
      if (mounted) setState(() => _wasteSettings = settings);
    } catch (_) {}
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

  Set<String> get _quantityOnlyTypeNames =>
      _wasteTypes.where((t) => t.isQuantityOnly).map((t) => t.mainType).toSet();

  Set<String> get _noSiteWeightTypeNames =>
      _wasteTypes.where((t) => t.noSiteWeight).map((t) => t.mainType).toSet();

  Map<String, String> get _quantityLabelByType => {
        for (final t in _wasteTypes)
          if (t.isQuantityOnly || t.noSiteWeight) t.mainType: t.quantityLabelFor('default'),
      };

  /// Returns the short unit string for a quantity-only type, e.g. "bins".
  String _unitFor(String typeName) {
    final label = _quantityLabelByType[typeName] ?? 'Quantity (units)';
    final m = RegExp(r'\(([^)]+)\)').firstMatch(label);
    return m?.group(1) ?? 'units';
  }

  Future<void> _loadPrelinkedStock() async {
    setState(() => _loadingPrelinked = true);
    try {
      final items = await _wasteService
          .getStockItemsByIds(widget.load.selectedStockIds);
      if (mounted) {
        setState(() {
          final qtyOnly = _quantityOnlyTypeNames;
          for (final stock in items) {
            if (stock.status == WasteStockStatus.onSite) {
              _items.add(_ItemEntry.fromStock(
                stock,
                isQuantityOnly: qtyOnly.contains(stock.wasteType) ||
                    qtyOnly.contains(stock.subtype),
                isNoSiteWeight: _noSiteWeightTypeNames.contains(stock.wasteType) ||
                    _noSiteWeightTypeNames.contains(stock.subtype),
              ));
            }
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPrelinked = false);
    }
  }

  bool get _canSubmit {
    if (_driverCtrl.text.trim().isEmpty ||
        _regCtrl.text.trim().isEmpty ||
        _paperDocCtrl.text.trim().isEmpty ||
        _items.isEmpty ||
        _isSubmitting) {
      return false;
    }
    if (_photosRequired) {
      final itemsHavePhotos = _items.every(
        (i) =>
            i.photoPaths.isNotEmpty || i.isQuantityOnly || i.isNoSiteWeight,
      );
      if (!itemsHavePhotos || _loadPhotoPaths.isEmpty) return false;
    }
    if (_signatureRequired && _signatureBytes == null) return false;
    return true;
  }

  String get _submitHelperText {
    final parts = <String>[
      'Complete driver details, paper document reference, and add at least one item',
    ];
    if (_photosRequired) {
      parts.add('add photos where required');
      parts.add('capture loaded-truck photos');
    }
    if (_signatureRequired) parts.add('capture driver signature');
    return '${parts.join(', ')}.';
  }

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

  bool get _canLinkOnSiteStock =>
      loadCanLinkOnSiteStock(widget.load.mainWasteType, _wasteTypes);

  Future<void> _addFromStock() async {
    if (!_canLinkOnSiteStock) return;
    final alreadyOnLoad =
        _items.where((i) => i.stockId != null).map((i) => i.stockId!).toSet();
    final picked = await WasteStockLinkSheet.show(
      context,
      wasteType: stockLinkParentType(widget.load.mainWasteType),
      subtypeFilter: widget.load.mainWasteType == WasteStockTypes.copperWaste
          ? {WasteStockTypes.copperRods, WasteStockTypes.copperNuggets}
          : stockSubtypeFilterForChips(_contractorLinkedTypes, _wasteTypes),
      initialSelectedIds: alreadyOnLoad.toList(),
      includeManagerOnlyStock: true,
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
            _items.add(_ItemEntry.fromStock(
              stock,
              isQuantityOnly: _quantityOnlyTypeNames.contains(stock.wasteType) ||
                  _quantityOnlyTypeNames.contains(stock.subtype),
              isNoSiteWeight: _noSiteWeightTypeNames.contains(stock.wasteType) ||
                  _noSiteWeightTypeNames.contains(stock.subtype),
            ));
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
    final typeNames = itemSubtypeOptionsForChips(available, _wasteTypes);

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
            photosRequired: _photosRequired,
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _items.add(_ItemEntry(
        subtype: result.subtype,
        weightKg: result.weightKg,
        quantity: result.quantity,
        notes: result.notes,
        photoPaths: result.localPhotoPaths,
        isQuantityOnly: result.isQuantityOnly,
        isNoSiteWeight: result.isNoSiteWeight,
      )));
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
    _timeOut ??= TimeOfDay.now();
    final skipWeighbridge = loadSkipsWeighbridge(
      mainWasteType: widget.load.mainWasteType,
      allTypes: _wasteTypes,
      itemQuantityOnlyFlags: _items.map((i) => i.isQuantityOnly),
    );

    try {
      // Build itemsData for submitCollection — includes both stock-sourced and fresh items
      final itemsData = _items.map((i) => {
        'subtype': i.subtype,
        'weight_kg': i.weightKg,
        'quantity': i.quantity,
        'notes': i.notes,
        'localPhotoPaths': i.photoPaths,
        'is_quantity_only': i.isQuantityOnly,
        'is_no_site_weight': i.isNoSiteWeight,
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
        securityName: currentEmployee?.name,
        timeIn: _formatTime(_timeIn),
        timeOut: _formatTime(_timeOut!),
        paperDocumentRef: _paperDocCtrl.text.trim(),
        itemsData: itemsData,
        loadPhotoPaths: _loadPhotoPaths,
        signatureLocalPath: _signatureTempPath,
        contractorId: widget.load.contractorId,
        isQuantityOnly: skipWeighbridge,
      );

      // Mark confirmed stock items as loaded. If the load itself was queued
      // offline we must also queue the stock updates — marking stock online
      // against a load that isn't in Firestore yet would leave orphaned state.
      if (confirmedStockIds.isNotEmpty) {
        if (!result.queuedOffline) {
          await _wasteService.markStockLoaded(confirmedStockIds, widget.load.id!);
        } else {
          await _wasteService.queueMarkStockLoaded(confirmedStockIds, widget.load.id!);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.queuedOffline
                  ? 'Collection saved offline — will sync when connection returns'
                  : skipWeighbridge
                      ? 'Collection submitted — awaiting admin cost review'
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
                  Text('Contractor: ${widget.load.contractorName ?? widget.load.contractorId}',
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

            const SizedBox(height: 14),

            TextField(
              controller: _paperDocCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Paper document reference *',
                hintText: 'Number from the physical gate docket',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            if (currentEmployee?.name != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Security Officer'),
                subtitle: Text(currentEmployee!.name!),
              ),

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
                    if (_canLinkOnSiteStock)
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
            if (_canLinkOnSiteStock)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Link saved on-site stock on collection day, or capture fresh items with new photos.',
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
                  _photosRequired
                      ? 'At least one item with a photo is required.'
                      : 'At least one item is required.',
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
                              Text(item.isQuantityOnly
                                  ? '${item.quantity ?? 0} ${_unitFor(item.subtype)}'
                                  : '${item.weightKg.toStringAsFixed(1)} kg${item.quantity != null ? ' • qty ${item.quantity}' : ''}'),
                              if (_photosRequired && item.photoPaths.isEmpty &&
                                  !item.isQuantityOnly && !item.isNoSiteWeight)
                                Text('⚠ Photo required',
                                    style: TextStyle(fontSize: 12, color: Colors.red.shade700))
                              else if (item.photoPaths.isNotEmpty)
                                Text('${item.photoPaths.length} photo(s)',
                                    style: TextStyle(fontSize: 12, color: appColors.wasteGreen)),
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
            if (_photosRequired && _loadPhotoPaths.isEmpty)
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
                  label: Text(_signatureRequired
                      ? 'Capture Driver Signature *'
                      : 'Capture Driver Signature (optional)'),
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
                  _submitHelperText,
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
  /// Mirrors WasteType.isQuantityOnly — weight is meaningless for these items.
  final bool isQuantityOnly;
  /// Mirrors WasteType.noSiteWeight — weight recorded at weighbridge, not on-site.
  final bool isNoSiteWeight;

  const _ItemEntry({
    required this.subtype,
    required this.weightKg,
    this.quantity,
    this.notes,
    required this.photoPaths,
    this.stockId,
    this.isQuantityOnly = false,
    this.isNoSiteWeight = false,
  });

  /// Create an entry from a pre-loaded stock item.
  /// Photos are the stock item's existing URLs (stored as paths for display).
  factory _ItemEntry.fromStock(WasteStockItem stock, {bool isQuantityOnly = false, bool isNoSiteWeight = false}) {
    return _ItemEntry(
      subtype: stock.subtype.isNotEmpty ? stock.subtype : stock.wasteType,
      weightKg: stock.estimatedWeightKg ?? 0.0,
      quantity: isQuantityOnly ? stock.quantity : null,
      notes: stock.notes ?? (stock.ibcNumber != null ? 'IBC ${stock.ibcNumber}' : null),
      photoPaths: stock.photos,
      stockId: stock.id,
      isQuantityOnly: isQuantityOnly,
      isNoSiteWeight: isNoSiteWeight,
    );
  }
}

