import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/waste_service.dart';

/// Result returned by [WasteAddItemSheet].
class WasteAddItemSheetResult {
  final String subtype;
  final double weightKg;
  final int? quantity;
  final String? notes;
  final List<String> localPhotoPaths;
  final bool isQuantityOnly;
  final bool isNoSiteWeight;

  const WasteAddItemSheetResult({
    required this.subtype,
    required this.weightKg,
    this.quantity,
    this.notes,
    required this.localPhotoPaths,
    this.isQuantityOnly = false,
    this.isNoSiteWeight = false,
  });
}

/// Shared bottom-sheet for adding a fresh waste item to a load.
///
/// Used from both [WasteBeginCollectionScreen] and [WasteLoadDetailScreen].
/// Pass [quantityOnlyTypeNames] and [quantityLabelByType] to enable the
/// quantity-only mode for types such as IBC Bins (no weight entry).
class WasteAddItemSheet extends StatefulWidget {
  const WasteAddItemSheet({
    super.key,
    required this.types,
    this.defaultType,
    this.title = 'Add Waste Item',
    this.quantityOnlyTypeNames = const {},
    this.noSiteWeightTypeNames = const {},
    this.quantityLabelByType = const {},
  });

  final List<String> types;
  final String? defaultType;
  final String title;
  final Set<String> quantityOnlyTypeNames;
  /// Types where weight is not recorded on-site; guard records quantity only
  /// but the weighbridge step is still required.
  final Set<String> noSiteWeightTypeNames;
  final Map<String, String> quantityLabelByType;

  @override
  State<WasteAddItemSheet> createState() => _WasteAddItemSheetState();
}

class _WasteAddItemSheetState extends State<WasteAddItemSheet> {
  final WasteService _wasteService = WasteService();
  late String? _wasteType;
  final _weightCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    final def = widget.defaultType;
    _wasteType = (def != null && widget.types.contains(def))
        ? def
        : (widget.types.isNotEmpty ? widget.types.first : null);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _isQtyOnly =>
      _wasteType != null && widget.quantityOnlyTypeNames.contains(_wasteType);

  bool get _isNoSiteWeight =>
      _wasteType != null && widget.noSiteWeightTypeNames.contains(_wasteType);

  /// True when weight field should be hidden and quantity is required.
  bool get _hideWeight => _isQtyOnly || _isNoSiteWeight;

  String get _qtyLabel => widget.quantityLabelByType[_wasteType] ?? 'Quantity';

  bool get _valid {
    if (_wasteType == null) return false;
    if (_hideWeight) return (int.tryParse(_qtyCtrl.text) ?? 0) > 0;
    return (double.tryParse(_weightCtrl.text) ?? 0) > 0;
  }

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
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.types.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _wasteType,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Waste Type', isDense: true),
                  items: widget.types
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _wasteType = v;
                    _weightCtrl.clear();
                    _qtyCtrl.clear();
                    // Default qty to 1 for no-site-weight types
                    if (v != null && widget.noSiteWeightTypeNames.contains(v) && _qtyCtrl.text.isEmpty) {
                      _qtyCtrl.text = '1';
                    }
                  }),
                )
              else
                TextField(
                  decoration:
                      const InputDecoration(labelText: 'Waste Type *', isDense: true),
                  onChanged: (v) =>
                      setState(() => _wasteType = v.isEmpty ? null : v),
                ),
              const SizedBox(height: 10),
              if (_hideWeight) ...[
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '$_qtyLabel *',
                    isDense: true,
                    helperText: _isNoSiteWeight ? 'Weight will be confirmed at weighbridge' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                TextField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Weight (kg) *',
                      isDense: true,
                      suffixText: 'kg'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Quantity (optional)', isDense: true),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                    labelText: 'Notes (optional)', isDense: true),
              ),
              const SizedBox(height: 12),
              Text('Photos (${_photos.length})',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF616161))),
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
                        child: CircularProgressIndicator(strokeWidth: 2)),
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
                          child: Image.file(File(_photos[i]),
                              width: 60, height: 60, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close,
                                  size: 12, color: Colors.white),
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
                      ? () => Navigator.pop(
                            context,
                            WasteAddItemSheetResult(
                              subtype: _wasteType!,
                              weightKg: _hideWeight
                                  ? 0.0
                                  : double.parse(_weightCtrl.text),
                              quantity: _qtyCtrl.text.isNotEmpty
                                  ? int.tryParse(_qtyCtrl.text)
                                  : null,
                              notes: _notesCtrl.text.isNotEmpty
                                  ? _notesCtrl.text
                                  : null,
                              localPhotoPaths: List.of(_photos),
                              isQuantityOnly: _isQtyOnly,
                              isNoSiteWeight: _isNoSiteWeight,
                            ),
                          )
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
