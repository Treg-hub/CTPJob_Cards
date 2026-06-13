import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen Code-128 scanner. Pops with the scanned string, or null if the
/// user backs out. Used by the IBC receive flow.
class InkBarcodeScanScreen extends StatefulWidget {
  const InkBarcodeScanScreen({super.key});

  @override
  State<InkBarcodeScanScreen> createState() => _InkBarcodeScanScreenState();
}

class _InkBarcodeScanScreenState extends State<InkBarcodeScanScreen> {
  final MobileScannerController _controller =
      MobileScannerController(formats: const [BarcodeFormat.code128]);
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan IBC barcode')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_handled) return;
          final code =
              capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
          if (code != null && code.isNotEmpty) {
            _handled = true;
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
