import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/waste_settings.dart';
import '../models/waste_stock_item.dart';
import '../services/waste_service.dart';
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../widgets/waste_app_bar.dart';

class WasteAddStockItemScreen extends ConsumerStatefulWidget {
  const WasteAddStockItemScreen({
    super.key,
    this.existingItem,
  });

  final WasteStockItem? existingItem;

  @override
  ConsumerState<WasteAddStockItemScreen> createState() =>
      _WasteAddStockItemScreenState();
}

class _WasteAddStockItemScreenState extends ConsumerState<WasteAddStockItemScreen> {
  final WasteService _wasteService = WasteService();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<String> _wasteTypeOptions = [];
  String? _selectedWasteType;
  final List<String> _savedPhotoUrls = [];
  final List<String> _newLocalPhotos = [];
  final List<String> _removedPhotoUrls = [];
  bool _addingPhoto = false;
  bool _isSaving = false;
  WasteSettings? _wasteSettings;

  bool get _isEdit => widget.existingItem != null;
  bool get _photosRequired => _wasteSettings?.photosRequired ?? false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingItem;
    if (existing != null) {
      _selectedWasteType = existing.subtype.isNotEmpty
          ? existing.subtype
          : existing.wasteType;
      if (existing.estimatedWeightKg != null) {
        _weightCtrl.text = existing.estimatedWeightKg!.toString();
      }
      if (existing.notes != null) {
        _notesCtrl.text = existing.notes!;
      }
      _savedPhotoUrls.addAll(existing.photos);
    }
    _loadWasteTypes();
    _loadWasteSettings();
  }

  Future<void> _loadWasteSettings() async {
    try {
      final settings = await _wasteService.getWasteSettings();
      if (mounted) setState(() => _wasteSettings = settings);
    } catch (_) {}
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWasteTypes() async {
    try {
      final types = await _wasteService
          .watchWasteTypes()
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (mounted) {
        setState(() {
          _wasteTypeOptions = types
              .map((t) => t.mainType)
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          if (_selectedWasteType == null && _wasteTypeOptions.isNotEmpty) {
            _selectedWasteType = _wasteTypeOptions.first;
          } else if (_selectedWasteType != null &&
              !_wasteTypeOptions.contains(_selectedWasteType)) {
            _wasteTypeOptions = [..._wasteTypeOptions, _selectedWasteType!];
          }
        });
      }
    } catch (_) {}
  }

  int get _totalPhotoCount =>
      _savedPhotoUrls.length + _newLocalPhotos.length;

  bool get _isValid =>
      _selectedWasteType != null &&
      (!_photosRequired || _totalPhotoCount >= 1);

  Future<void> _addPhoto(ImageSource source) async {
    if (!guardPersonaSubmit(context)) return;
    setState(() => _addingPhoto = true);
    try {
      final path = await _wasteService.pickAndCompressPhotoFromSource(source);
      if (path != null && mounted) setState(() => _newLocalPhotos.add(path));
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  void _removeSavedPhoto(String url) {
    setState(() {
      _savedPhotoUrls.remove(url);
      if (!_removedPhotoUrls.contains(url)) {
        _removedPhotoUrls.add(url);
      }
    });
  }

  Future<void> _save() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_isValid) return;
    setState(() => _isSaving = true);
    try {
      final double? weight = _weightCtrl.text.isNotEmpty
          ? double.tryParse(_weightCtrl.text)
          : null;
      final notes =
          _notesCtrl.text.isNotEmpty ? _notesCtrl.text.trim() : null;

      if (_isEdit) {
        final id = widget.existingItem!.id;
        if (id == null) throw Exception('Stock item has no id');
        final result = await _wasteService.updateStockItem(
          stockId: id,
          subtype: _selectedWasteType!,
          estimatedWeightKg: weight,
          notes: notes,
          keptPhotoUrls: List.from(_savedPhotoUrls),
          newLocalPhotoPaths: List.from(_newLocalPhotos),
          removedPhotoUrls: List.from(_removedPhotoUrls),
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.queuedOffline
                    ? 'Saved offline — will sync when connection returns'
                    : 'Stock item updated',
              ),
              backgroundColor:
                  result.queuedOffline ? Colors.orange : Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        final item = WasteStockItem(
          wasteType: _selectedWasteType!,
          subtype: _selectedWasteType!,
          estimatedWeightKg: weight,
          notes: notes,
          createdBy: resolveWriteActor(currentEmployee)?.clockNo ?? '',
          createdByName: currentEmployee?.name ?? '',
          createdAt: DateTime.now(),
        );
        final result = await _wasteService.addStockItem(
          item: item,
          localPhotoPaths: _newLocalPhotos,
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.queuedOffline
                    ? 'Saved offline — will sync when connection returns'
                    : 'Stock item recorded',
              ),
              backgroundColor:
                  result.queuedOffline ? Colors.orange : Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).appColors;

    return Scaffold(
      appBar: WasteAppBar(
        title: _isEdit ? 'Edit Stock Item' : 'Record Stock Item',
        isOnSite: currentEmployee?.isOnSite,
        actions: [
          TextButton(
            onPressed: (_isValid && !_isSaving) ? _save : null,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Waste type *',
              style: TextStyle(fontSize: 12, color: appColors.textMuted),
            ),
            const SizedBox(height: 4),
            _wasteTypeOptions.isEmpty && _selectedWasteType == null
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    initialValue: _selectedWasteType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _wasteTypeOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedWasteType = v),
                  ),
            const SizedBox(height: 16),
            TextField(
              controller: _weightCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Estimated weight (optional)',
                suffixText: 'kg',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _photosRequired ? 'Photos * (min 1)' : 'Photos (optional)',
              style: TextStyle(fontSize: 12, color: appColors.textMuted),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton.outlined(
                  onPressed:
                      _addingPhoto ? null : () => _addPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Camera',
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _addingPhoto
                      ? null
                      : () => _addPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  tooltip: 'Gallery',
                ),
                if (_addingPhoto) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            if (_savedPhotoUrls.isNotEmpty || _newLocalPhotos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savedPhotoUrls.length + _newLocalPhotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final isSaved = i < _savedPhotoUrls.length;
                    final url = isSaved ? _savedPhotoUrls[i] : null;
                    final path = isSaved
                        ? null
                        : _newLocalPhotos[i - _savedPhotoUrls.length];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: isSaved
                              ? Image.network(
                                  url!,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 64,
                                    height: 64,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                )
                              : Image.file(
                                  File(path!),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              if (isSaved) {
                                _removeSavedPhoto(url!);
                              } else {
                                setState(() => _newLocalPhotos
                                    .removeAt(i - _savedPhotoUrls.length));
                              }
                            },
                            child: const CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.red,
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (_photosRequired && _totalPhotoCount == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'At least 1 photo required',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                ),
              ),
          ],
        ),
      ),
    );
  }
}