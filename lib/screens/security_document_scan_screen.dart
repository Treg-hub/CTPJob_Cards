import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/parsed_document.dart';
import '../services/security_document_parser.dart';
import '../utils/barcode_payload_util.dart';

/// PDF417 scanner for SA license disc and ID documents.
class SecurityDocumentScanScreen extends StatefulWidget {
  const SecurityDocumentScanScreen({
    super.key,
    this.title = 'Scan Document',
    this.expectedType,
  });

  final String title;
  final SecurityDocumentType? expectedType;

  @override
  State<SecurityDocumentScanScreen> createState() =>
      _SecurityDocumentScanScreenState();
}

class _SecurityDocumentScanScreenState
    extends State<SecurityDocumentScanScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: _formatsFor(widget.expectedType),
    returnImage: true,
    detectionSpeed: widget.expectedType == SecurityDocumentType.driverLicence
        ? DetectionSpeed.unrestricted
        : DetectionSpeed.noDuplicates,
  );

  static List<BarcodeFormat> _formatsFor(SecurityDocumentType? type) {
    if (type == SecurityDocumentType.driverLicence) {
      return const [BarcodeFormat.pdf417];
    }
    return const [BarcodeFormat.pdf417, BarcodeFormat.dataMatrix];
  }

  ParsedDocument? _result;
  bool _torchOn = false;
  bool _autoTorchTried = false;
  int _frameCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _setTorch(bool on) async {
    if (_torchOn == on) return;
    await _controller.toggleTorch();
    if (mounted) setState(() => _torchOn = on);
  }

  void _maybeAutoTorch(Uint8List? image) {
    if (_autoTorchTried || _torchOn || image == null || image.isEmpty) return;
    _frameCount++;
    if (_frameCount < 8) return;

    var sum = 0;
    final step = (image.length / 400).floor().clamp(1, image.length);
    var samples = 0;
    for (var i = 0; i < image.length; i += step) {
      sum += image[i];
      samples++;
    }
    final avg = sum / samples;
    if (avg < 72) {
      _autoTorchTried = true;
      _setTorch(true);
      HapticFeedback.lightImpact();
    }
  }

  void _onDetect(BarcodeCapture capture) {
    _maybeAutoTorch(capture.image);

    for (final b in capture.barcodes) {
      final raw = BarcodePayloadUtil.extractPayload(b);
      if (raw == null || raw.isEmpty) continue;
      final parsed = switch (widget.expectedType) {
        SecurityDocumentType.licenseDisc =>
          SecurityDocumentParser.parseLicenseDisc(raw),
        SecurityDocumentType.idDocument =>
          SecurityDocumentParser.parseIdDocument(raw),
        SecurityDocumentType.driverLicence =>
          SecurityDocumentParser.parseDriverLicence(raw),
        _ => SecurityDocumentParser.parseBarcode(raw),
      };
      final accepted = parsed.hasVehicleData ||
          parsed.hasIdData ||
          parsed.hasDriverLicenceData;
      if (!accepted) continue;
      if (!mounted) return;
      setState(() => _result = parsed);
      HapticFeedback.mediumImpact();
      return;
    }
  }

  void _manualEntry() async {
    final isDisc = widget.expectedType == SecurityDocumentType.licenseDisc;
    final isDriverLicence =
        widget.expectedType == SecurityDocumentType.driverLicence;
    final regCtrl = TextEditingController(text: _result?.vehicleReg ?? '');
    final makeCtrl = TextEditingController(text: _result?.vehicleMake ?? '');
    final idCtrl = TextEditingController(text: _result?.idNumber ?? '');
    final firstCtrl = TextEditingController(text: _result?.firstName ?? '');
    final lastCtrl = TextEditingController(text: _result?.lastName ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isDisc
              ? 'Enter disc details'
              : isDriverLicence
                  ? 'Enter licence details'
                  : 'Enter ID details',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDisc) ...[
                TextField(
                  controller: regCtrl,
                  decoration: const InputDecoration(labelText: 'Vehicle reg'),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextField(
                  controller: makeCtrl,
                  decoration: const InputDecoration(labelText: 'Make'),
                ),
              ] else ...[
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: 'ID number'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: firstCtrl,
                  decoration: const InputDecoration(labelText: 'First names'),
                ),
                TextField(
                  controller: lastCtrl,
                  decoration: const InputDecoration(labelText: 'Surname'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() {
      _result = isDisc
          ? SecurityDocumentParser.manualLicenseDisc(
              vehicleReg: regCtrl.text,
              vehicleMake:
                  makeCtrl.text.isEmpty ? null : makeCtrl.text,
            )
          : isDriverLicence
              ? SecurityDocumentParser.manualDriverLicence(
                  idNumber: idCtrl.text,
                  firstName:
                      firstCtrl.text.isEmpty ? null : firstCtrl.text,
                  lastName: lastCtrl.text.isEmpty ? null : lastCtrl.text,
                )
              : SecurityDocumentParser.manualIdDocument(
                  idNumber: idCtrl.text,
                  firstName:
                      firstCtrl.text.isEmpty ? null : firstCtrl.text,
                  lastName: lastCtrl.text.isEmpty ? null : lastCtrl.text,
                );
    });
  }

  void _use() {
    if (_result == null) return;
    Navigator.pop(context, _result);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => _setTorch(!_torchOn),
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
          TextButton(onPressed: _manualEntry, child: const Text('Manual')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                const _Pdf417GuideOverlay(),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (widget.expectedType) {
                    SecurityDocumentType.licenseDisc =>
                      'Vehicle licence disc: aim at the PDF417 barcode. '
                          'Not the thin 1D barcode on the edge. Hold steady.',
                    SecurityDocumentType.driverLicence =>
                      "Driver's licence card: flip to the back and scan the "
                          'PDF417 barcode there. The front 1D barcode does not '
                          'contain name/ID data.',
                    _ =>
                      'Aim at the PDF417 on the back of the ID card. '
                          'Hold steady, use torch in low light.',
                  },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (r != null) ...[
                  if (r.vehicleReg != null)
                    Text('Reg: ${r.vehicleReg}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (r.expiryDate != null)
                    Text('Expiry: ${r.expiryDate!.toLocal().toString().split(' ').first}'),
                  if (r.vehicleMake != null) Text('Make: ${r.vehicleMake}'),
                  if (r.vehicleModel != null) Text('Model: ${r.vehicleModel}'),
                  if (r.fullName != null) Text('Name: ${r.fullName}'),
                  if (r.idNumber != null) Text('ID: ${r.idNumber}'),
                  if (r.manualEntry)
                    Text('Manual entry',
                        style: TextStyle(color: scheme.primary, fontSize: 12)),
                ] else
                  const Text('Waiting for scan…'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: r != null ? _use : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Use'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pdf417GuideOverlay extends StatelessWidget {
  const _Pdf417GuideOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _Pdf417GuidePainter(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _Pdf417GuidePainter extends CustomPainter {
  _Pdf417GuidePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width * 0.88;
    final frameH = size.height * 0.22;
    final left = (size.width - frameW) / 2;
    final top = (size.height - frameH) / 2;
    final rect = Rect.fromLTWH(left, top, frameW, frameH);

    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _Pdf417GuidePainter old) => old.color != color;
}