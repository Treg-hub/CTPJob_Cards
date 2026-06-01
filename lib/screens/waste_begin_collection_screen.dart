import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/waste_load.dart';
import '../models/waste_type.dart';
import '../services/waste_service.dart';
import '../main.dart' show currentEmployee;
import 'waste_signature_screen.dart';

/// Guard-facing screen: complete a collection on a [scheduled] load.
/// The guard fills in driver name, vehicle reg, waste items (with photos),
/// and captures the driver signature, then submits.
/// Calls [WasteService.submitCollection] which transitions the load to [pending_weighbridge].
class WasteBeginCollectionScreen extends ConsumerStatefulWidget {
  const WasteBeginCollectionScreen({super.key, required this.load});

  /// The scheduled load to collect against.
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
  final List<_ItemEntry> _items = [];
  Uint8List? _signatureBytes;
  String? _signatureTempPath;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadWasteTypes();
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
      if (mounted) setState(() => _wasteTypes = types);
    } catch (_) {}
  }

  bool get _canSubmit =>
      _driverCtrl.text.trim().isNotEmpty &&
      _regCtrl.text.trim().isNotEmpty &&
      _items.isNotEmpty &&
      _items.every((i) => i.photoPaths.isNotEmpty) &&
      _signatureBytes != null &&
      !_isSubmitting;

  Future<void> _addItem() async {
    final types = _wasteTypes
        .where((t) => t.mainType == widget.load.mainWasteType)
        .toList();
    final subtypes = types.isNotEmpty ? types.first.subtypes : <String>[];

    final result = await showDialog<_ItemEntry>(
      context: context,
      builder: (ctx) => _AddItemDialog(subtypes: subtypes),
    );
    if (result != null && mounted) {
      setState(() => _items.add(result));
    }
  }

  Future<void> _captureSignature() async {
    final bytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => WasteSignatureScreen(loadNumber: widget.load.loadNumber.isNotEmpty
            ? widget.load.loadNumber
            : widget.load.mainWasteType),
      ),
    );
    if (bytes != null && mounted) {
      // Save to temp file for submitCollection (which needs a file path)
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
      await _wasteService.submitCollection(
        loadId: widget.load.id!,
        driverName: _driverCtrl.text.trim(),
        vehicleReg: _regCtrl.text.trim(),
        collectedBy: currentEmployee?.clockNo ?? '',
        itemsData: _items.map((i) => {
          'subtype': i.subtype,
          'weight_kg': i.weightKg,
          'quantity': i.quantity,
          'notes': i.notes,
          'localPhotoPaths': i.photoPaths,
        }).toList(),
        signatureLocalPath: _signatureTempPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collection submitted — manager will enter weighbridge weight'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Begin Collection'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Load header (read-only) ──────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E7D32), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_shipping, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      Text(widget.load.mainWasteType,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Contractor ID: ${widget.load.contractorId}',
                      style: const TextStyle(fontSize: 13)),
                  Text(
                    'Expected: ${DateFormat('EEE d MMM, HH:mm').format(scheduledDate)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (widget.load.scheduledByName != null)
                    Text('Scheduled by: ${widget.load.scheduledByName}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (widget.load.scheduledNotes != null &&
                      widget.load.scheduledNotes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Manager note: ${widget.load.scheduledNotes}',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('Driver Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            // ── Driver name ──────────────────────────────────
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

            // ── Vehicle registration ─────────────────────────
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
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ],
            ),

            if (_items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'At least one item with a photo is required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.subtype, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${item.weightKg} kg${item.quantity != null ? ' • qty ${item.quantity}' : ''}'),
                              Text('${item.photoPaths.length} photo(s)',
                                  style: const TextStyle(fontSize: 12, color: Colors.green)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => setState(() => _items.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                );
              }),

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
                      border: Border.all(color: Colors.green),
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

            // ── Submit ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Collection', style: TextStyle(fontSize: 16)),
              ),
            ),

            const SizedBox(height: 8),
            if (!_canSubmit && !_isSubmitting)
              const Text(
                'Complete all fields, add at least one item with photo, and capture signature to submit.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
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

  const _ItemEntry({
    required this.subtype,
    required this.weightKg,
    this.quantity,
    this.notes,
    required this.photoPaths,
  });
}

// ---------------------------------------------------------------------------
// Add item dialog
// ---------------------------------------------------------------------------

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.subtypes});
  final List<String> subtypes;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final WasteService _wasteService = WasteService();
  String? _subtype;
  final _weightCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final List<String> _photos = [];
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    if (widget.subtypes.isNotEmpty) _subtype = widget.subtypes.first;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _subtype != null &&
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
    return AlertDialog(
      title: const Text('Add Waste Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtypes.isNotEmpty) ...[
              const Text('Subtype', style: TextStyle(fontSize: 12, color: Colors.grey)),
              DropdownButton<String>(
                value: _subtype,
                isExpanded: true,
                items: widget.subtypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _subtype = v),
              ),
            ] else ...[
              TextField(
                decoration: const InputDecoration(labelText: 'Subtype *', isDense: true),
                onChanged: (v) => setState(() => _subtype = v.isEmpty ? null : v),
              ),
            ],
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
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                          child: const CircleAvatar(radius: 9, backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 12, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, _ItemEntry(
                  subtype: _subtype!,
                  weightKg: double.parse(_weightCtrl.text),
                  quantity: _qtyCtrl.text.isNotEmpty ? int.tryParse(_qtyCtrl.text) : null,
                  notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
                  photoPaths: List.of(_photos),
                ))
              : null,
          child: const Text('Add Item'),
        ),
      ],
    );
  }
}
