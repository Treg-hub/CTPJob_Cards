import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/waste_service.dart';
import '../utils/screen_insets.dart';
import '../utils/waste_type_routing.dart';

/// Result of the Copper Skins dual-bin gross capture sheet.
class WasteCopperSkinsItemSheetResult {
  final String subtype;
  final double weightKg;
  final int quantity;
  final String? notes;
  final List<String> localPhotoPaths;
  final double grossBin1Kg;
  final double grossBin2Kg;
  final double tareBin1Kg;
  final double tareBin2Kg;

  const WasteCopperSkinsItemSheetResult({
    required this.subtype,
    required this.weightKg,
    this.quantity = 2,
    this.notes,
    required this.localPhotoPaths,
    required this.grossBin1Kg,
    required this.grossBin2Kg,
    required this.tareBin1Kg,
    required this.tareBin2Kg,
  });
}

/// Fixed two-bin capture for Copper Skins.
///
/// Guard enters full (gross) weights for Bin 1 and Bin 2. Empty bin tares come
/// from Pulse [waste_settings]. Net = (G1+G2) − (T1+T2). Client ticket still
/// follows on Pulse weighbridge.
class WasteCopperSkinsItemSheet extends StatefulWidget {
  const WasteCopperSkinsItemSheet({
    super.key,
    required this.subtype,
    required this.tareBin1Kg,
    required this.tareBin2Kg,
    this.title = 'Copper Skins weight',
    this.photosRequired = false,
  });

  final String subtype;
  final double tareBin1Kg;
  final double tareBin2Kg;
  final String title;
  final bool photosRequired;

  @override
  State<WasteCopperSkinsItemSheet> createState() =>
      _WasteCopperSkinsItemSheetState();
}

class _WasteCopperSkinsItemSheetState extends State<WasteCopperSkinsItemSheet> {
  final WasteService _wasteService = WasteService();
  final _gross1Ctrl = TextEditingController();
  final _gross2Ctrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void dispose() {
    _gross1Ctrl.dispose();
    _gross2Ctrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _taresOk => widget.tareBin1Kg > 0 && widget.tareBin2Kg > 0;

  double? get _net {
    final g1 = double.tryParse(_gross1Ctrl.text.trim());
    final g2 = double.tryParse(_gross2Ctrl.text.trim());
    if (g1 == null || g2 == null) return null;
    return copperSkinsNetKg(
      grossBin1Kg: g1,
      grossBin2Kg: g2,
      tareBin1Kg: widget.tareBin1Kg,
      tareBin2Kg: widget.tareBin2Kg,
    );
  }

  bool get _valid {
    if (!_taresOk) return false;
    if (widget.photosRequired && _photos.isEmpty) return false;
    return _net != null;
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
    final net = _net;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Weigh both full bins. Empty weights come from Pulse settings. '
            'Net skins kg = (Bin1 full + Bin2 full) − (Bin1 empty + Bin2 empty). '
            'Client weighbridge ticket is still entered later on Pulse.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_taresOk)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Text(
                    'Bin tares are not configured. An admin must set Bin 1 and '
                    'Bin 2 empty weights in Pulse → Settings → Waste before collection.',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Empty (tare): Bin 1 ${widget.tareBin1Kg.toStringAsFixed(1)} kg · '
                    'Bin 2 ${widget.tareBin2Kg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              TextField(
                controller: _gross1Ctrl,
                enabled: _taresOk,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Gross Bin 1 (full) *',
                  isDense: true,
                  suffixText: 'kg',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _gross2Ctrl,
                enabled: _taresOk,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Gross Bin 2 (full) *',
                  isDense: true,
                  suffixText: 'kg',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: net != null
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: net != null
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  net != null
                      ? 'Net skins weight: ${net.toStringAsFixed(1)} kg'
                      : 'Net skins weight: —',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: net != null
                        ? Colors.green.shade900
                        : Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.photosRequired
                    ? 'Photos * (${_photos.length})'
                    : 'Photos (optional, ${_photos.length})',
                style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: _addingPhoto
                        ? null
                        : () => _addPhoto(ImageSource.camera),
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
                          child: Image.file(
                            File(_photos[i]),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.removeAt(i)),
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
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeBottomBar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _valid
                      ? () {
                          final g1 = double.parse(_gross1Ctrl.text.trim());
                          final g2 = double.parse(_gross2Ctrl.text.trim());
                          final n = _net!;
                          Navigator.pop(
                            context,
                            WasteCopperSkinsItemSheetResult(
                              subtype: widget.subtype,
                              weightKg: n,
                              quantity: 2,
                              notes: _notesCtrl.text.isNotEmpty
                                  ? _notesCtrl.text
                                  : null,
                              localPhotoPaths: List.of(_photos),
                              grossBin1Kg: g1,
                              grossBin2Kg: g2,
                              tareBin1Kg: widget.tareBin1Kg,
                              tareBin2Kg: widget.tareBin2Kg,
                            ),
                          );
                        }
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
            ],
          ),
        ),
      ],
    );
  }
}
