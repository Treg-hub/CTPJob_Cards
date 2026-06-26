import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/employee.dart';
import '../services/scan_tester_service.dart';
import '../theme/app_theme.dart';
import '../utils/barcode_payload_util.dart';

/// Admin-only barcode capture for parser development.
/// Saves to `pulse_scan_samples` — does not submit gate or ink receive flows.
class ScanTesterScreen extends StatefulWidget {
  const ScanTesterScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<ScanTesterScreen> createState() => _ScanTesterScreenState();
}

class _ScanTesterScreenState extends State<ScanTesterScreen> {
  /// Single controller for the screen lifetime — mobile_scanner binds to the
  /// controller only in [initState]; swapping controllers without a new widget
  /// key leaves a disposed camera (blank preview).
  final MobileScannerController _controller = MobileScannerController(
    returnImage: true,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final ScanTesterService _service = ScanTesterService();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _manualController = TextEditingController();

  String _module = 'security';
  String _useCase = 'licence_disc';
  bool _multiMode = false;
  bool _torchOn = false;
  bool _autoTorchTried = false;
  int _frameCount = 0;
  bool _saving = false;
  String _lastFormat = 'unknown';
  final List<ScanBarcodeEntry> _accumulated = [];
  String? _lastPayload;

  bool _acceptsBarcodeFormat(BarcodeFormat? format) {
    final fmt = ScanTesterService.normalizeBarcodeFormat(format);
    switch (_useCase) {
      case 'driver_licence':
        return fmt == 'pdf417';
      case 'licence_disc':
      case 'national_id':
        return fmt == 'pdf417' || fmt == 'datamatrix';
      default:
        return true;
    }
  }

  void _resetCaptureState({String? useCase, String? module}) {
    setState(() {
      if (module != null) _module = module;
      if (useCase != null) _useCase = useCase;
      _lastPayload = null;
      _lastFormat = 'unknown';
      _manualController.clear();
      _accumulated.clear();
      _autoTorchTried = false;
      _frameCount = 0;
    });
  }

  void _onUseCaseChanged(String? useCase) {
    if (useCase == null || useCase == _useCase) return;
    _resetCaptureState(useCase: useCase);
  }

  @override
  void dispose() {
    _controller.dispose();
    _notesController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  String get _primaryPayload {
    if (_multiMode && _accumulated.isNotEmpty) return _accumulated.first.payload;
    if (_lastPayload != null && _lastPayload!.trim().isNotEmpty) {
      return _lastPayload!.trim();
    }
    return _manualController.text.trim();
  }

  Map<String, dynamic>? get _parserPreview {
    final payload = _primaryPayload;
    if (payload.isEmpty) return null;
    return ScanTesterService.buildParserPreview(
      module: _module,
      useCase: _useCase,
      rawPayload: payload,
      allBarcodes: _multiMode && _accumulated.isNotEmpty ? _accumulated : null,
    );
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
      if (!_acceptsBarcodeFormat(b.format)) continue;
      final raw = BarcodePayloadUtil.extractPayload(b);
      if (raw == null || raw.isEmpty) continue;
      final fmt = ScanTesterService.normalizeBarcodeFormat(b.format);
      if (!mounted) return;
      setState(() {
        _lastFormat = fmt;
        _lastPayload = raw;
        if (_multiMode) {
          if (!_accumulated.any((e) => e.payload == raw)) {
            _accumulated.add(ScanBarcodeEntry(format: fmt, payload: raw));
          }
        }
      });
      HapticFeedback.mediumImpact();
      return;
    }
  }

  Future<void> _pasteManual() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() {
      _lastFormat = 'unknown';
      _lastPayload = text;
      _manualController.text = text;
    });
  }

  Future<void> _save() async {
    final payload = _primaryPayload;
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan or paste a barcode first')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not signed in — cannot save sample'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.saveSample(
        module: _module,
        useCase: _useCase,
        barcodeFormat: _lastFormat,
        rawPayload: payload,
        allBarcodes: _multiMode && _accumulated.isNotEmpty ? _accumulated : null,
        notes: _notesController.text,
        capturedByUid: uid,
        capturedByClockNo: widget.employee.clockNo,
        capturedByName: widget.employee.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sample saved — review in Pulse Settings › Scan Tester'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _accumulated.clear();
        _manualController.clear();
        _notesController.clear();
        _lastPayload = null;
        _lastFormat = 'unknown';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useCases = ScanTesterCatalog.useCases[_module] ?? const ['unknown'];
    final preview = _parserPreview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Tester'),
        actions: [
          IconButton(
            onPressed: () => _setTorch(!_torchOn),
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanGuidePainter(color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _useCase == 'driver_licence'
                        ? "Driver's licence: scan the PDF417 on the back of the card. "
                            'The front barcode (restrictions/categories) does not decode. '
                            'Licence disc and driver licence are different documents.'
                        : _useCase == 'licence_disc'
                            ? 'Vehicle licence disc: aim at the PDF417. Plate reg, make and '
                                'model are read from the scan. Not the thin 1D edge barcode.'
                            : _module == 'security'
                                ? 'National ID: PDF417 on the back of the card.'
                                : 'Capture raw barcodes for parser development. '
                                    'Review saved samples in CTP Pulse Settings.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _module,
                          decoration: const InputDecoration(
                            labelText: 'Module',
                            isDense: true,
                          ),
                          items: ScanTesterCatalog.modules
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            _resetCaptureState(
                              module: v,
                              useCase:
                                  ScanTesterCatalog.useCases[v]?.first ?? 'unknown',
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('usecase-$_module-$_useCase'),
                          initialValue: useCases.contains(_useCase) ? _useCase : useCases.first,
                          decoration: const InputDecoration(
                            labelText: 'Use case',
                            isDense: true,
                          ),
                          items: useCases
                              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: _onUseCaseChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Multi-barcode mode'),
                    subtitle: const Text('Accumulate several codes (e.g. IBC labels)'),
                    value: _multiMode,
                    onChanged: (v) => setState(() {
                      _multiMode = v;
                      if (!v) _accumulated.clear();
                    }),
                  ),
                  if (_multiMode && _accumulated.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ..._accumulated.map(
                      (e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.payload,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(e.format, style: const TextStyle(fontSize: 10)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(
                            () => _accumulated.removeWhere((x) => x.payload == e.payload),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualController,
                    decoration: InputDecoration(
                      labelText: 'Raw payload',
                      hintText: 'Scan above or paste manually',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        onPressed: _pasteManual,
                        tooltip: 'Paste from clipboard',
                      ),
                    ),
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_primaryPayload.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Format: $_lastFormat',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    if (BarcodePayloadUtil.isBinaryPayload(_primaryPayload))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          BarcodePayloadUtil.displayPayload(_primaryPayload),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      isDense: true,
                    ),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 12),
                    Text('Parser preview', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        JsonEncoder.withIndent('  ').convert(preview),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving || _primaryPayload.isEmpty ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save sample'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandOrange,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  _ScanGuidePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width * 0.88;
    final frameH = size.height * 0.35;
    final left = (size.width - frameW) / 2;
    final top = (size.height - frameH) / 2;
    final rect = Rect.fromLTWH(left, top, frameW, frameH);

    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter old) => old.color != color;
}