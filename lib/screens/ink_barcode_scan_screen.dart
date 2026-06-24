import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/ink_barcode_parser.dart';

/// Code-128 IBC scanner. Accumulates every barcode seen and merges them through
/// [parseIbcBarcodeSet], so the operator can point at the single GS1 + SSCC label
/// OR the three separate codes (IBC / colour / weight) — whichever is readable.
/// Pops with the merged [IbcScanResult], or null if cancelled.
class InkBarcodeScanScreen extends StatefulWidget {
  const InkBarcodeScanScreen({
    super.key,
    this.existingIbcNumbers = const {},
  });

  /// IBC numbers already captured on the receive screen (8-digit serials).
  final Set<String> existingIbcNumbers;

  @override
  State<InkBarcodeScanScreen> createState() => _InkBarcodeScanScreenState();
}

class _InkBarcodeScanScreenState extends State<InkBarcodeScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.code128],
    returnImage: true,
  );
  final Set<String> _seen = {};
  IbcScanResult _result = const IbcScanResult();
  bool _torchOn = false;
  bool _autoTorchTried = false;
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _torchOn = _controller.torchEnabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isDuplicate {
    final n = _result.ibcNumber;
    return n != null && widget.existingIbcNumbers.contains(n);
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

    var added = false;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty && _seen.add(v)) added = true;
    }
    if (!added || !mounted) return;

    final merged = parseIbcBarcodeSet(_seen);
    final prevIbc = _result.ibcNumber;
    setState(() => _result = merged);

    if (merged.ibcNumber != null && merged.ibcNumber != prevIbc) {
      if (widget.existingIbcNumbers.contains(merged.ibcNumber)) {
        HapticFeedback.heavyImpact();
      } else if (merged.isComplete) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  void _clear() => setState(() {
        _seen.clear();
        _result = const IbcScanResult();
      });

  void _use() {
    if (!_result.hasAnything) return;
    if (_isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'IBC ${_result.ibcNumber} is already on this receipt.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, _result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _result;

    Widget field(String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(label,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
              Expanded(
                child: Text(
                  value ?? '—',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: value == null ? scheme.onSurfaceVariant : null,
                  ),
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan IBC'),
        actions: [
          IconButton(
            onPressed: () => _setTorch(!_torchOn),
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: _torchOn ? 'Turn torch off' : 'Turn torch on',
          ),
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                const _ScanGuideOverlay(),
                if (_isDuplicate)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: scheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'IBC ${r.ibcNumber} already scanned on this receipt',
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerHighest,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Centre the barcode in the frame',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                field('IBC no.', r.ibcNumber),
                field('Colour', r.colour),
                field('Weight', r.weightKg == null ? null : '${r.weightKg} kg'),
                field('Charge', r.charge),
                if (r.weightTruncated)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Weight may be partial — check it.',
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: r.hasAnything && !_isDuplicate ? _use : null,
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

/// Dimmed mask with corner brackets to help centre the label in frame.
class _ScanGuideOverlay extends StatelessWidget {
  const _ScanGuideOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanGuidePainter(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  _ScanGuidePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width * 0.82;
    final frameH = size.height * 0.28;
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
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 28.0;

    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * len, 0), stroke);
      canvas.drawLine(o, o + Offset(0, dy * len), stroke);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter old) => old.color != color;
}