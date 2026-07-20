import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/security_receipt_parse_result.dart';
import 'security_receipt_parser.dart';

/// On-device receipt OCR for company-car costing.
///
/// Uses ML Kit Text Recognition (Latin) then [SecurityReceiptParser].
/// Does **not** upload Storage or write Firestore — callers keep the local
/// image path and only upload on Save via [SecurityService.uploadCostReceipt].
class SecurityReceiptOcrService {
  TextRecognizer? _recognizer;

  TextRecognizer get _textRecognizer =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Run OCR + field extraction on a local image file.
  Future<SecurityReceiptParseResult> parseImageFile(
    String localPath, {
    List<String> categories = const [],
    DateTime? now,
  }) async {
    final input = InputImage.fromFilePath(localPath);
    final recognized = await _textRecognizer.processImage(input);
    final rawText = _linesToText(recognized);
    return SecurityReceiptParser.parse(
      rawText,
      categories: categories,
      now: now,
    );
  }

  static String _linesToText(RecognizedText recognized) {
    final buffer = StringBuffer();
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(t);
      }
    }
    // Fallback if block/line structure empty but text present
    if (buffer.isEmpty && recognized.text.trim().isNotEmpty) {
      return recognized.text.trim();
    }
    return buffer.toString();
  }

  Future<void> close() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
