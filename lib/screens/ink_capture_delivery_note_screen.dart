import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ink_purchase_order.dart';
import '../models/ink_shipment.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../services/ink_delivery_note_ocr_service.dart';
import '../utils/ink_delivery_note_flow.dart';
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
  bool _ocrBusy = false;
  String? _localPath;
  String _contentType = 'image/jpeg';
  final _noteNumberController = TextEditingController();
  final _ocr = InkDeliveryNoteOcrService();

  /// Last value suggested by OCR (if any).
  String? _ocrSuggestion;

  /// Operator must confirm the number matches the paper before save.
  bool _numberConfirmed = false;

  String? _ocrHint;

  String get _title {
    if (widget.shipment != null) {
      return 'Delivery note · ${widget.shipment!.id}';
    }
    return 'Delivery note · ${widget.order!.pulseRef}';
  }

  bool get _canSave {
    final note = _noteNumberController.text.trim();
    return !_busy &&
        !_ocrBusy &&
        _localPath != null &&
        note.length >= 3 &&
        _numberConfirmed;
  }

  @override
  void dispose() {
    _noteNumberController.dispose();
    _ocr.close();
    super.dispose();
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
      _ocrSuggestion = null;
      _numberConfirmed = false;
      _ocrHint = null;
      _noteNumberController.clear();
      _ocrBusy = true;
    });
    await _runOcr(compressed);
  }

  Future<void> _runOcr(String path) async {
    try {
      final result = await _ocr.parseImageFile(path);
      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        if (result.hasCandidate) {
          _ocrSuggestion = result.noteNumber;
          _noteNumberController.text = result.noteNumber!;
          _numberConfirmed = false;
          _ocrHint =
              'Read from photo — please check it matches the paper next to '
              '“Delivery Note”, then confirm below.';
        } else {
          _ocrSuggestion = null;
          _ocrHint =
              'Couldn’t read the delivery note number — type it from the top '
              'of the paper (e.g. WL817898), then confirm.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrSuggestion = null;
        _ocrHint =
            'Couldn’t scan the photo — type the delivery note number from the '
            'paper, then confirm.';
      });
    }
  }

  void _onNoteNumberChanged(String _) {
    setState(() {
      // Any edit after OCR / confirm requires a fresh confirm.
      _numberConfirmed = false;
    });
  }

  Future<void> _submit() async {
    if (_localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Take or pick a photo of the signed delivery note'),
        ),
      );
      return;
    }
    final noteNumber = _noteNumberController.text.trim();
    if (noteNumber.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter the delivery note number from the top of the paper '
            '(e.g. WL817898 next to “Delivery Note”)',
          ),
        ),
      );
      return;
    }
    if (!_numberConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirm the delivery note number matches the paper before saving',
          ),
        ),
      );
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    setState(() => _busy = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      final kind = widget.shipment != null ? 'shipment' : 'local_po';
      final docId = widget.shipment?.id ?? widget.order!.id;
      await ref.read(inkServiceProvider).attachDeliveryNote(
            kind: kind,
            docId: docId,
            localFilePath: _localPath!,
            contentType: _contentType,
            capturedBy: emp?.clockNo ?? emp?.name ?? 'mobile',
            noteNumber: noteNumber,
          );
      if (!mounted) return;
      invalidateInkReceivedPeriodLists(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery note saved — load complete')),
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
              child: Text(
                'Selected: ${_localPath!.split(RegExp(r'[\\/]')).last}',
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _ocrBusy
                      ? null
                      : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _ocrBusy
                      ? null
                      : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          if (_localPath != null) ...[
            const SizedBox(height: 20),
            Text(
              'Delivery note number',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Number printed at the top of the paper next to “Delivery Note” '
              '(e.g. WL817898). We try to read it from the photo — you confirm.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (_ocrBusy) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Reading delivery note number…',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (_ocrHint != null && !_ocrBusy) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _ocrSuggestion != null
                      ? scheme.primaryContainer.withValues(alpha: 0.45)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  _ocrHint!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _noteNumberController,
              enabled: !_busy && !_ocrBusy,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/]')),
              ],
              decoration: InputDecoration(
                labelText: 'Delivery note number *',
                hintText: 'e.g. WL817898',
                border: const OutlineInputBorder(),
                suffixIcon: _ocrSuggestion != null &&
                        _noteNumberController.text.trim().toUpperCase() ==
                            _ocrSuggestion
                    ? Icon(Icons.document_scanner_outlined,
                        color: scheme.primary)
                    : null,
              ),
              textInputAction: TextInputAction.done,
              onChanged: _onNoteNumberChanged,
              onSubmitted: (_) {
                if (_canSave) void _submit();
              },
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _numberConfirmed,
              onChanged: _busy ||
                      _ocrBusy ||
                      _noteNumberController.text.trim().length < 3
                  ? null
                  : (v) => setState(() => _numberConfirmed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I confirm this number matches the paper'),
              subtitle: Text(
                _ocrSuggestion != null
                    ? 'Scanned value — correct it above if the photo misread it.'
                    : 'Type carefully, then tick to enable save.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _canSave ? _submit : null,
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
