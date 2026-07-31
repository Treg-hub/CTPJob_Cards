import 'dart:typed_data';

/// Local PDF payload for the in-app viewer (mobile file path or web bytes).
///
/// Never holds a public Storage download URL — bytes/path come only from
/// authenticated [PressManualCacheService] downloads.
class PressManualPdfSource {
  final String sourceName;
  final String? filePath;
  final Uint8List? bytes;

  const PressManualPdfSource._({
    required this.sourceName,
    this.filePath,
    this.bytes,
  });

  factory PressManualPdfSource.file({
    required String sourceName,
    required String path,
  }) {
    return PressManualPdfSource._(sourceName: sourceName, filePath: path);
  }

  factory PressManualPdfSource.memory({
    required String sourceName,
    required Uint8List bytes,
  }) {
    return PressManualPdfSource._(sourceName: sourceName, bytes: bytes);
  }

  bool get hasFile => filePath != null && filePath!.isNotEmpty;
  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}
