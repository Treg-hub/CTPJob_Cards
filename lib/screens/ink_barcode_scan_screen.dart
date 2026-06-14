import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/ink_barcode_parser.dart';

/// Code-128 IBC scanner. Accumulates every barcode seen and merges them through
/// [parseIbcBarcodes], so the operator can point at the single GS1 + SSCC label
/// OR the three separate codes (IBC / colour / weight) — whichever is readable.
/// Pops with the merged [IbcScanResult], or null if cancelled.
class InkBarcodeScanScreen extends StatefulWidget {
  const InkBarcodeScanScreen({super.key});

  @override
  State<InkBarcodeScanScreen> createState() => _InkBarcodeScanScreenState();
}

class _InkBarcodeScanScreenState extends State<InkBarcodeScanScreen> {
  final MobileScannerController _controller =
      MobileScannerController(formats: const [BarcodeFormat.code128]);
  final Set<String> _seen = {};
  IbcScanResult _result = const IbcScanResult();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    var added = false;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty && _seen.add(v)) added = true;
    }
    if (added && mounted) {
      setState(() => _result = parseIbcBarcodeSet(_seen));
    }
  }

  void _clear() => setState(() {
        _seen.clear();
        _result = const IbcScanResult();
      });

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
                      style: Theme.of(context).textTheme.labelMedium)),
              Text(value ?? '—',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: value == null ? scheme.onSurfaceVariant : null)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan IBC'),
        actions: [
          IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.refresh),
              tooltip: 'Clear'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerHighest,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Point at the main label or the 3 codes',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                field('IBC no.', r.ibcNumber),
                field('Colour', r.colour),
                field('Weight',
                    r.weightKg == null ? null : '${r.weightKg} kg'),
                field('Charge', r.charge),
                if (r.weightTruncated)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Weight may be partial — check it.',
                        style: TextStyle(color: scheme.error, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: r.hasAnything
                      ? () => Navigator.pop(context, r)
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Use'),
                  style:
                      FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
