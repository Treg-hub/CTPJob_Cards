/// Pure text extraction for the paper transporter delivery-note number.
///
/// Target is the code printed next to **Delivery Note** at the top of the form
/// (e.g. `WL817898`), not the shipment id and not customer/container refs.
class InkDeliveryNoteParseResult {
  const InkDeliveryNoteParseResult({
    this.noteNumber,
    this.confidence = 0,
    this.rawSnippet,
  });

  /// Normalised candidate (upper-case, no spaces), or null if none.
  final String? noteNumber;

  /// 0–1 heuristic confidence.
  final double confidence;

  /// Nearby OCR text used for debugging / UI hint.
  final String? rawSnippet;

  bool get hasCandidate =>
      noteNumber != null && noteNumber!.trim().length >= 3;
}

class InkDeliveryNoteParser {
  InkDeliveryNoteParser._();

  /// Letter(s) + digits, common on these forms (WL817898).
  static final RegExp _letterDigit = RegExp(
    r'\b([A-Z]{1,4}\d{4,10})\b',
    caseSensitive: false,
  );

  /// Digits only — weaker fallback (avoid short dates etc.).
  static final RegExp _digitsOnly = RegExp(r'\b(\d{6,10})\b');

  static final RegExp _deliveryNoteLabel = RegExp(
    r'delivery\s*note',
    caseSensitive: false,
  );

  /// Tokens that are usually other fields on the same form.
  static final Set<String> _rejectExact = {
    'DELIVERY',
    'NOTE',
    'CUSTOMER',
    'REFERENCE',
    'OPERATOR',
    'VESSEL',
    'CONTAINER',
    'NUMBER',
    'DETAILS',
  };

  static InkDeliveryNoteParseResult parse(String rawText) {
    final text = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) {
      return const InkDeliveryNoteParseResult();
    }

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1) Same line as "Delivery Note … WL817898"
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_deliveryNoteLabel.hasMatch(line)) continue;

      final afterLabel = line.replaceFirst(_deliveryNoteLabel, ' ').trim();
      final sameLine = _pickBestCandidate(afterLabel, preferLetterDigit: true);
      if (sameLine != null) {
        return InkDeliveryNoteParseResult(
          noteNumber: sameLine,
          confidence: 0.95,
          rawSnippet: line,
        );
      }

      // 2) Next 1–2 lines after the label (number alone on the right/below)
      final window = <String>[line];
      if (i + 1 < lines.length) window.add(lines[i + 1]);
      if (i + 2 < lines.length) window.add(lines[i + 2]);
      final nearby = _pickBestCandidate(
        window.join(' '),
        preferLetterDigit: true,
      );
      if (nearby != null) {
        return InkDeliveryNoteParseResult(
          noteNumber: nearby,
          confidence: 0.88,
          rawSnippet: window.join(' · '),
        );
      }
    }

    // 3) Whole document: letter+digit tokens that look like DN numbers,
    // preferring early lines (header region).
    final scored = <_Scored>[];
    for (var i = 0; i < lines.length; i++) {
      for (final m in _letterDigit.allMatches(lines[i].toUpperCase())) {
        final t = _normalize(m.group(1)!);
        if (!_isPlausibleNoteNumber(t)) continue;
        // Header bias: first ~8 lines score higher
        final headerBoost = i < 8 ? 0.15 : 0;
        scored.add(_Scored(t, 0.55 + headerBoost, lines[i]));
      }
    }
    if (scored.isNotEmpty) {
      scored.sort((a, b) => b.score.compareTo(a.score));
      final best = scored.first;
      return InkDeliveryNoteParseResult(
        noteNumber: best.value,
        confidence: best.score.clamp(0.0, 0.8),
        rawSnippet: best.snippet,
      );
    }

    // 4) Weak: long digit run next to a delivery-note label only
    for (var i = 0; i < lines.length; i++) {
      if (!_deliveryNoteLabel.hasMatch(lines[i])) continue;
      final window = [
        lines[i],
        if (i + 1 < lines.length) lines[i + 1],
      ].join(' ');
      final d = _pickDigitsCandidate(window);
      if (d != null) {
        return InkDeliveryNoteParseResult(
          noteNumber: d,
          confidence: 0.55,
          rawSnippet: window,
        );
      }
    }

    return const InkDeliveryNoteParseResult();
  }

  static String? _pickBestCandidate(
    String chunk, {
    required bool preferLetterDigit,
  }) {
    final upper = chunk.toUpperCase();
    final letterDigit = _letterDigit
        .allMatches(upper)
        .map((m) => _normalize(m.group(1)!))
        .where(_isPlausibleNoteNumber)
        .toList();
    if (letterDigit.isNotEmpty) {
      // Prefer WL-style (2 letters + 6 digits) typical of this transporter
      letterDigit.sort((a, b) {
        final sa = _shapeScore(a);
        final sb = _shapeScore(b);
        return sb.compareTo(sa);
      });
      return letterDigit.first;
    }
    if (!preferLetterDigit) return null;
    return _pickDigitsCandidate(chunk);
  }

  static String? _pickDigitsCandidate(String chunk) {
    final hits = _digitsOnly
        .allMatches(chunk)
        .map((m) => m.group(1)!)
        .where((d) => d.length >= 6 && d.length <= 10)
        .toList();
    if (hits.isEmpty) return null;
    // Prefer 6–8 digit runs (DN-like) over longer IDs
    hits.sort((a, b) {
      final da = (a.length - 7).abs();
      final db = (b.length - 7).abs();
      return da.compareTo(db);
    });
    return hits.first;
  }

  static String _normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static bool _isPlausibleNoteNumber(String t) {
    if (t.length < 5 || t.length > 14) return false;
    if (_rejectExact.contains(t)) return false;
    // ISO container-ish: 4 letters + 7 digits
    if (RegExp(r'^[A-Z]{4}\d{7}$').hasMatch(t)) return false;
    // Customer ref style often SD + long digits
    if (RegExp(r'^SD\d{8,}$').hasMatch(t)) return false;
    // Pure year / short codes
    if (RegExp(r'^\d{4}$').hasMatch(t)) return false;
    return true;
  }

  static int _shapeScore(String t) {
    // WL817898 → high; longer mixed tokens lower
    final m = RegExp(r'^([A-Z]{1,3})(\d{5,8})$').firstMatch(t);
    if (m != null) return 100 + (m.group(1)!.length == 2 ? 10 : 0);
    if (RegExp(r'^[A-Z]{1,4}\d{4,10}$').hasMatch(t)) return 50;
    return 10;
  }
}

class _Scored {
  _Scored(this.value, this.score, this.snippet);
  final String value;
  final double score;
  final String snippet;
}
