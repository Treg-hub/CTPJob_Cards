import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ink_purchase_order.dart';
import '../models/ink_shipment.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';

/// Capture signed transporter delivery note for a received shipment or local PO.
class InkCaptureDeliveryNoteScreen extends ConsumerStatefulWidget {
  const InkCaptureDeliveryNoteScreen.shipment({
    super.key,
    required InkShipment this.shipment,
  }) : order = null;

  const InkCaptureDeliveryNoteScreen.localOrder({
    super.key,
    required InkPurchaseOrder this.order,
  }) : shipment = null;

  final InkShipment? shipment;
  final InkPurchaseOrder? order;

  @override
  ConsumerState<InkCaptureDeliveryNoteScreen> createState() =>
      _InkCaptureDeliveryNoteScreenState();
}

class _InkCaptureDeliveryNoteScreenState
    extends ConsumerState<InkCaptureDeliveryNoteScreen> {
  bool _busy = false;
  String? _localPath;
  String _contentType = 'image/jpeg';

  String get _title {
    if (widget.shipment != null) {
      return 'Delivery note · ${widget.shipment!.id}';
    }
    return 'Delivery note · ${widget.order!.pulseRef}';
  }

  /// Same practical compression as job-card breakdown photos
  /// (`create_job_card_screen`: 1024 edge, quality 70, no EXIF).
  Future<String> _compressForUpload(String path) async {
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/dn_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      path,
      outPath,
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
      rotate: 0,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    return result?.path ?? path;
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    // Full capture first — compression step matches job cards (not picker quality).
    final picked = await picker.pickImage(source: source);
    if (picked == null) return;
    final compressed = await _compressForUpload(picked.path);
    if (!mounted) return;
    setState(() {
      _localPath = compressed;
      _contentType = 'image/jpeg';
    });
  }

  Future<void> _submit() async {
    if (_localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Take or pick a photo of the signed delivery note')),
      );
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    setState(() => _busy = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      final kind = widget.shipment != null ? 'shipment' : 'local_po';
      final docId =
          widget.shipment?.id ?? widget.order!.id;
      await ref.read(inkServiceProvider).attachDeliveryNote(
            kind: kind,
            docId: docId,
            localFilePath: _localPath!,
            contentType: _contentType,
            capturedBy: emp?.clockNo ?? emp?.name ?? 'mobile',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery note saved')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save delivery note: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          ScreenInsets.scrollBottomFullScreen(context),
        ),
        children: [
          Text(
            'Photograph the signed transporter delivery note. Stock is already '
            'on the ledger — this completes proof of delivery for stores / Sage.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_localPath != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Selected: ${_localPath!.split(RegExp(r'[\\/]')).last}'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_busy ? 'Uploading…' : 'Save delivery note'),
          ),
        ],
      ),
    );
  }
}
