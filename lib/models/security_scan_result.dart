import 'parsed_document.dart';

/// Result from [SecurityDocumentScanScreen] when [structuredResult] is true.
class SecurityScanResult {
  const SecurityScanResult({
    this.document,
    this.skipped = false,
    this.cantScan = false,
  });

  final ParsedDocument? document;
  final bool skipped;
  final bool cantScan;

  bool get hasDocument => document != null;

  factory SecurityScanResult.success(ParsedDocument document) =>
      SecurityScanResult(document: document);

  factory SecurityScanResult.skippedScan() =>
      const SecurityScanResult(skipped: true);

  factory SecurityScanResult.cantScanDisc() =>
      const SecurityScanResult(cantScan: true);
}