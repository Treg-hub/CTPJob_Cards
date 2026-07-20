/// Structured fields extracted from a receipt image OCR text dump.
///
/// Used only to prefill the Add Company Car Cost form. The manager always
/// reviews before save; this model is never written to Firestore as-is.
class SecurityReceiptParseResult {
  final String rawText;
  final double? amountZar;
  final DateTime? costDate;
  final String? description;
  /// Must be one of the live `costTypeSuggestions` when non-null.
  final String? suggestedCategory;
  /// Heuristic 0–1 (not an ML Kit score). High when a TOTAL line was used.
  final double confidence;
  final List<String> warnings;

  const SecurityReceiptParseResult({
    required this.rawText,
    this.amountZar,
    this.costDate,
    this.description,
    this.suggestedCategory,
    this.confidence = 0,
    this.warnings = const [],
  });

  bool get hasUsableFields =>
      amountZar != null ||
      costDate != null ||
      (description != null && description!.trim().isNotEmpty) ||
      suggestedCategory != null;
}
