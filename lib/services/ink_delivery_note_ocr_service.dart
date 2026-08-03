import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ink_delivery_note_parser.dart';

/// On-device OCR for transporter delivery-note photos (Ink POD).
///
/// Uses ML Kit Text Recognition (Latin) then [InkDeliveryNoteParser].
/// Does not upload Storage or write Firestore — capture screen uploads on save.
class InkDeliveryNoteOcrService {
  TextRecognizer? _recognizer;

  TextRecognizer get _textRecognizer =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Run OCR + DN-number extraction on a local image file.
  Future<InkDeliveryNoteParseResult> parseImageFile(String localPath) async {
    final input = InputImage.fromFilePath(localPath);
    final recognized = await _textRecognizer.processImage(input);
    final rawText = _linesToText(recognized);
    return InkDeliveryNoteParser.parse(rawText);
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
