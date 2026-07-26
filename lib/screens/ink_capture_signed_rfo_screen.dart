import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ink_purchase_order.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';

/// Capture signed board RFO, then enter Pastel RFO # + order # (import gate).
class InkCaptureSignedRfoScreen extends ConsumerStatefulWidget {
  const InkCaptureSignedRfoScreen({super.key, required this.order});

  final InkPurchaseOrder order;

  @override
  ConsumerState<InkCaptureSignedRfoScreen> createState() =>
      _InkCaptureSignedRfoScreenState();
}

class _InkCaptureSignedRfoScreenState
    extends ConsumerState<InkCaptureSignedRfoScreen> {
  bool _busy = false;
  String? _localPath;
  String _contentType = 'image/jpeg';
  bool _photoSaved = false;
  final _pastelRfoCtrl = TextEditingController();
  final _erpCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _photoSaved = widget.order.signedRfoPdfPath != null &&
        widget.order.signedRfoPdfPath!.isNotEmpty;
    _pastelRfoCtrl.text = widget.order.pastelRfoNumber ?? '';
    _erpCtrl.text = widget.order.erpOrderNumber ?? '';
  }

  @override
  void dispose() {
    _pastelRfoCtrl.dispose();
    _erpCtrl.dispose();
    super.dispose();
  }

  Future<String> _compressForUpload(String path) async {
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/signed_rfo_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
    final picked = await picker.pickImage(source: source);
    if (picked == null) return;
    final compressed = await _compressForUpload(picked.path);
    if (!mounted) return;
    setState(() {
      _localPath = compressed;
      _contentType = 'image/jpeg';
    });
  }

  Future<void> _submitPhoto() async {
    if (_localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Take or pick a photo of the signed RFO')),
      );
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    setState(() => _busy = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).attachSignedRfo(
            orderId: widget.order.id,
            localFilePath: _localPath!,
            contentType: _contentType,
            capturedBy: emp?.clockNo ?? emp?.name ?? 'mobile',
          );
      if (!mounted) return;
      setState(() {
        _photoSaved = true;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed RFO saved — enter Pastel numbers')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save signed RFO: $e')),
      );
    }
  }

  Future<void> _submitPastel() async {
    final pastel = _pastelRfoCtrl.text.trim();
    final erp = _erpCtrl.text.trim();
    if (pastel.isEmpty || erp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both Pastel RFO number and Pastel order number'),
        ),
      );
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    setState(() => _busy = true);
    final emp = writeAttributionEmployee ??
        ref.read(currentEmployeeProvider).valueOrNull;
    try {
      await ref.read(inkServiceProvider).completePastelNumbers(
            orderId: widget.order.id,
            pastelRfoNumber: pastel,
            erpOrderNumber: erp,
            enteredBy: emp?.clockNo ?? emp?.name ?? 'mobile',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pastel numbers saved — Mark sent on CTP Pulse'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save Pastel numbers: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Signed RFO · ${widget.order.pulseRef}')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          ScreenInsets.scrollBottomFullScreen(context),
        ),
        children: [
          Text(
            widget.order.supplierName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _photoSaved
                ? 'Step 2 — enter Pastel RFO # and Pastel order #'
                : 'Step 1 — photograph the signed RFO',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          if (!_photoSaved) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_localPath != null) ...[
              const SizedBox(height: 12),
              Text('Photo ready', style: Theme.of(context).textTheme.labelLarge),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submitPhoto,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save signed RFO'),
            ),
          ] else ...[
            TextField(
              controller: _pastelRfoCtrl,
              decoration: const InputDecoration(
                labelText: 'Pastel RFO number',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _erpCtrl,
              decoration: const InputDecoration(
                labelText: 'Pastel order number',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submitPastel,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Pastel numbers'),
            ),
          ],
        ],
      ),
    );
  }
}
