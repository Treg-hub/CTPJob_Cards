import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/parsed_document.dart';
import '../models/security_scan_result.dart';
import '../services/security_document_parser.dart';
import '../utils/barcode_payload_util.dart';
import '../utils/screen_insets.dart';

/// PDF417 scanner for SA license disc and ID documents.
class SecurityDocumentScanScreen extends StatefulWidget {
  const SecurityDocumentScanScreen({
    super.key,
    this.title = 'Scan Document',
    this.expectedType,
    this.autoConfirmOnDetect = false,
    this.structuredResult = false,
    this.allowSkip = false,
    this.skipLabel = "Can't scan",
    this.showCantScanDisc = false,
  });

  final String title;
  final SecurityDocumentType? expectedType;

  /// When true, pop as soon as a valid document is parsed (no Use tap).
  final bool autoConfirmOnDetect;

  /// When true, pop [SecurityScanResult] instead of [ParsedDocument].
  final bool structuredResult;

  /// Bottom action to skip scanning (e.g. licence not available).
  final bool allowSkip;
  final String skipLabel;

  /// Bottom action when the licence disc cannot be scanned.
  final bool showCantScanDisc;

  @override
  State<SecurityDocumentScanScreen> createState() =>
      _SecurityDocumentScanScreenState();
}

class _SecurityDocumentScanScreenState
    extends State<SecurityDocumentScanScreen> {
  /// Match Scan Tester: do not restrict formats on the controller — some devices
  /// omit [Barcode.rawDecodedBytes] when formats are narrowed to PDF417 only.
  late final MobileScannerController _controller = MobileScannerController(
    returnImage: true,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  static bool _acceptsBarcodeFormat(
    SecurityDocumentType? expected,
    BarcodeFormat? format,
  ) {
    final name = (format?.name ?? '').toLowerCase();
    final fmt = name.contains('pdf')
        ? 'pdf417'
        : name.contains('data_matrix') || name.contains('datamatrix')
            ? 'datamatrix'
            : 'other';
    return switch (expected) {
      SecurityDocumentType.driverLicence => fmt == 'pdf417',
      SecurityDocumentType.licenseDisc ||
      SecurityDocumentType.idDocument =>
        fmt == 'pdf417' || fmt == 'datamatrix',
      _ => true,
    };
  }

  ParsedDocument? _result;
  bool _torchOn = false;
  bool _autoTorchTried = false;
  int _frameCount = 0;
  bool _confirmed = false;
  int _rejectedScanCount = 0;
  static const int _manualEntryHintThreshold = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop(dynamic value) {
    if (!mounted || _confirmed) return;
    _confirmed = true;
    Navigator.pop(context, value);
  }

  void _popDocument(ParsedDocument document) {
    if (widget.structuredResult) {
      _pop(SecurityScanResult.success(document));
    } else {
      _pop(document);
    }
  }

  void _popSkipped() {
    if (widget.structuredResult) {
      _pop(SecurityScanResult.skippedScan());
    } else {
      _pop(null);
    }
  }

  void _popCantScanDisc() {
    _pop(SecurityScanResult.cantScanDisc());
  }

  Future<void> _setTorch(bool on) async {
    if (!guardPersonaSubmit(context)) return;
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

  void _bumpRejectedScanCount() {
    _rejectedScanCount++;
    if (!mounted) return;
    if (_rejectedScanCount == _manualEntryHintThreshold) {
      setState(() {}); // trigger rebuild to show the manual-entry hint banner
    }
  }

  void _showWrongBarcodeHintOnce() {
    if (_rejectedScanCount != 1 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Wrong barcode detected — make sure you\'re scanning the correct PDF417 barcode.',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_confirmed) return;
    _maybeAutoTorch(capture.image);

    for (final b in capture.barcodes) {
      if (!_acceptsBarcodeFormat(widget.expectedType, b.format)) {
        _bumpRejectedScanCount();
        _showWrongBarcodeHintOnce();
        continue;
      }

      final preferBinary =
          widget.expectedType == SecurityDocumentType.driverLicence;
      final raw = BarcodePayloadUtil.extractPayload(
        b,
        preferBinary: preferBinary,
      );
      if (raw == null || raw.isEmpty) {
        _bumpRejectedScanCount();
        continue;
      }

      final parsed = switch (widget.expectedType) {
        SecurityDocumentType.licenseDisc =>
          SecurityDocumentParser.parseLicenseDisc(raw),
        SecurityDocumentType.idDocument =>
          SecurityDocumentParser.parseIdDocument(raw),
        SecurityDocumentType.driverLicence =>
          SecurityDocumentParser.parseDriverLicence(raw),
        _ => SecurityDocumentParser.parseBarcode(raw),
      };
      if (!_acceptsParsedResult(widget.expectedType, parsed, raw)) {
        _bumpRejectedScanCount();
        continue;
      }
      if (!mounted || _confirmed) return;

      if (widget.autoConfirmOnDetect) {
        HapticFeedback.mediumImpact();
        _popDocument(parsed);
        return;
      }

      setState(() => _result = parsed);
      HapticFeedback.mediumImpact();
      return;
    }
  }

  static bool _acceptsParsedResult(
    SecurityDocumentType? expected,
    ParsedDocument parsed,
    String raw,
  ) {
    if (expected == SecurityDocumentType.licenseDisc) {
      final reg = parsed.vehicleReg?.trim() ?? '';
      return reg.isNotEmpty;
    }
    if (parsed.hasVehicleData || parsed.hasIdData) return true;
    if (expected == SecurityDocumentType.driverLicence) {
      return parsed.documentType == SecurityDocumentType.driverLicence &&
          (parsed.hasDriverLicenceData ||
              BarcodePayloadUtil.isBinaryPayload(raw));
    }
    return parsed.hasDriverLicenceData;
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

    final manual = isDisc
        ? SecurityDocumentParser.manualLicenseDisc(
            vehicleReg: regCtrl.text,
            vehicleMake: makeCtrl.text.isEmpty ? null : makeCtrl.text,
          )
        : isDriverLicence
            ? SecurityDocumentParser.manualDriverLicence(
                idNumber: idCtrl.text,
                firstName: firstCtrl.text.isEmpty ? null : firstCtrl.text,
                lastName: lastCtrl.text.isEmpty ? null : lastCtrl.text,
              )
            : SecurityDocumentParser.manualIdDocument(
                idNumber: idCtrl.text,
                firstName: firstCtrl.text.isEmpty ? null : firstCtrl.text,
                lastName: lastCtrl.text.isEmpty ? null : lastCtrl.text,
              );

    if (widget.autoConfirmOnDetect) {
      _popDocument(manual);
    } else {
      setState(() => _result = manual);
    }
  }

  void _use() {
    final r = _result;
    if (r == null) return;
    _popDocument(r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final scheme = Theme.of(context).colorScheme;
    final hidePreview = widget.autoConfirmOnDetect;

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          const _Pdf417GuideOverlay(),
        ],
      ),
      bottomNavigationBar: Material(
        color: scheme.surfaceContainerHighest,
        child: SafeBottomBar(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (_rejectedScanCount >= _manualEntryHintThreshold)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Having trouble scanning? Try 'Manual' above, or check the torch.",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: _manualEntry,
                            child: const Text('Manual'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!hidePreview) ...[
                if (r != null) ...[
                  if (r.vehicleReg != null)
                    Text('Reg: ${r.vehicleReg}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (r.expiryDate != null)
                    Text(
                      'Expiry: ${r.expiryDate!.toLocal().toString().split(' ').first}',
                    ),
                  if (r.vehicleMake != null) Text('Make: ${r.vehicleMake}'),
                  if (r.vehicleModel != null) Text('Model: ${r.vehicleModel}'),
                  if (r.fullName != null) Text('Name: ${r.fullName}'),
                  if (r.idNumber != null) Text('ID: ${r.idNumber}'),
                  if (r.fullName == null &&
                      r.idNumber == null &&
                      r.rawPayload != null &&
                      BarcodePayloadUtil.isBinaryPayload(r.rawPayload!))
                    Text(
                      BarcodePayloadUtil.displayPayload(r.rawPayload!),
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                      ),
                    ),
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
              ] else
                const Text(
                  'Scanning… release when the barcode is in frame.',
                  style: TextStyle(fontSize: 12),
                ),
              if (widget.showCantScanDisc) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _popCantScanDisc,
                  child: const Text("Can't scan disc"),
                ),
              ],
              if (widget.allowSkip) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _popSkipped,
                  child: Text(widget.skipLabel),
                ),
              ],
            ],
          ),
        ),
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