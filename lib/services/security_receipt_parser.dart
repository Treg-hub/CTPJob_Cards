import '../models/security_receipt_parse_result.dart';

/// Pure-Dart field extraction from OCR text of SA till slips / invoices.
///
/// No ML Kit dependency — unit-test with golden text fixtures. Never writes
/// Firestore; only produces values to prefill the Add Cost form.
class SecurityReceiptParser {
  SecurityReceiptParser._();

  static final RegExp _amountToken = RegExp(
    r'(?:R\s*)?(\d{1,3}(?:[ \u00A0]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2})',
    caseSensitive: false,
  );

  static final RegExp _isoDate = RegExp(
    r'\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b',
  );

  static final RegExp _saDate = RegExp(
    r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
  );

  static final RegExp _totalLine = RegExp(
    r'\b(TOTAL|TOTAAL|AMOUNT\s*DUE|AMT\s*DUE|GRAND\s*TOTAL|'
    r'CARD\s*TOTAL|AMOUNT\s*PAID|BALANCE\s*DUE|TOTAL\s*DUE)\b',
    caseSensitive: false,
  );

  static final RegExp _noiseLine = RegExp(
    r'^(vat|btw|tax\s*invoice|tax\s*inv|thank|thanks|change|cashier|'
    r'tel|phone|www\.|http|reg\s*no|vat\s*no|company\s*reg|'
    r'pin|otp|auth|approval|merchant\s*id|mid\b|tid\b|rrn\b)',
    caseSensitive: false,
  );

  /// Keyword groups → preferred category labels (matched into live settings).
  static const Map<String, List<String>> _categoryKeywords = {
    'fuel': [
      'fuel',
      'petrol',
      'diesel',
      'unleaded',
      'ulp',
      'engen',
      'shell',
      'sasol',
      'caltex',
      'bp ',
      ' bp',
      'total energies',
      'total garage',
      'filling station',
      'litre',
      'liter',
      'l/100',
    ],
    'toll': ['toll', 'e-toll', 'etoll', 'sanral', 'tag'],
    'parking': ['parking', 'parkade', 'park fees', 'car park'],
    'wash': ['car wash', 'carwash', 'valet', 'wash bay'],
    'maintenance': [
      'service',
      'workshop',
      'mechanic',
      'tyre',
      'tire',
      'oil change',
      'spare',
      'repair',
    ],
    'fine': ['fine', 'traffic fine', 'aarto', 'infringement'],
    'escort': ['escort'],
  };

  /// Preferred settings labels per keyword group (first match wins).
  static const Map<String, List<String>> _categoryLabelPrefs = {
    'fuel': ['Fuel', 'Petrol', 'Diesel'],
    'toll': ['Toll'],
    'parking': ['Parking'],
    'wash': ['Car wash', 'Car Wash', 'Wash'],
    'maintenance': ['Maintenance', 'Service'],
    'fine': ['Fine'],
    'escort': ['Escort'],
  };

  /// Parse [rawText] from ML Kit (or fixture). [categories] is the live
  /// `security_settings.cost_type_suggestions` list — category is only set
  /// when it matches one of those strings (case-insensitive).
  static SecurityReceiptParseResult parse(
    String rawText, {
    List<String> categories = const [],
    DateTime? now,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const SecurityReceiptParseResult(rawText: '', confidence: 0);
    }

    final clock = now ?? DateTime.now();
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final warnings = <String>[];
    final amountResult = _extractAmount(lines, warnings);
    final costDate = _extractDate(lines, clock);
    final description = _extractDescription(lines);
    final category = _suggestCategory(text, categories);

    var confidence = 0.0;
    if (amountResult.amount != null) {
      confidence = amountResult.fromTotalLine ? 0.9 : 0.55;
      if (costDate != null) confidence = (confidence + 0.1).clamp(0.0, 1.0);
      if (description != null) confidence = (confidence + 0.05).clamp(0.0, 1.0);
    } else if (costDate != null || description != null) {
      confidence = 0.25;
      warnings.add('Could not read amount');
    }

    return SecurityReceiptParseResult(
      rawText: text,
      amountZar: amountResult.amount,
      costDate: costDate,
      description: description,
      suggestedCategory: category,
      confidence: confidence,
      warnings: warnings,
    );
  }

  // ── Amount ───────────────────────────────────────────────────────────────

  static ({double? amount, bool fromTotalLine}) _extractAmount(
    List<String> lines,
    List<String> warnings,
  ) {
    final totalCandidates = <double>[];
    final allCandidates = <double>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final amounts = _amountsInLine(line);
      if (amounts.isEmpty) {
        // TOTAL on this line, amount on next
        if (_totalLine.hasMatch(line) && i + 1 < lines.length) {
          final next = _amountsInLine(lines[i + 1]);
          totalCandidates.addAll(next);
        }
        continue;
      }

      allCandidates.addAll(amounts);
      if (_totalLine.hasMatch(line)) {
        totalCandidates.addAll(amounts);
      }
    }

    if (totalCandidates.length > 1) {
      warnings.add('Multiple total amounts found');
    }

    if (totalCandidates.isNotEmpty) {
      // Prefer the largest TOTAL (grand total usually > VAT subtotal mis-labels)
      final best = totalCandidates.reduce((a, b) => a >= b ? a : b);
      if (_isPlausibleAmount(best)) {
        return (amount: best, fromTotalLine: true);
      }
    }

    // Fallback: largest amount in the last third of the receipt
    if (allCandidates.isEmpty) {
      return (amount: null, fromTotalLine: false);
    }

    final start = (lines.length * 2 / 3).floor();
    final lateAmounts = <double>[];
    for (var i = start; i < lines.length; i++) {
      lateAmounts.addAll(_amountsInLine(lines[i]));
    }
    final pool = lateAmounts.isNotEmpty ? lateAmounts : allCandidates;
    final best = pool.reduce((a, b) => a >= b ? a : b);
    if (!_isPlausibleAmount(best)) {
      return (amount: null, fromTotalLine: false);
    }
    return (amount: best, fromTotalLine: false);
  }

  static List<double> _amountsInLine(String line) {
    final out = <double>[];
    for (final m in _amountToken.allMatches(line)) {
      final n = _parseAmount(m.group(1)!);
      if (n != null) out.add(n);
    }
    return out;
  }

  static double? _parseAmount(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\u00A0]'), '');
    // 1.234,56 (EU) vs 1,234.56 (US) vs 1234.56
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        // 1.234,56
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // 1,234.56
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      // 1234,56 or 1,234
      final parts = s.split(',');
      if (parts.length == 2 && parts[1].length == 2) {
        s = '${parts[0]}.${parts[1]}';
      } else {
        s = s.replaceAll(',', '');
      }
    }
    final v = double.tryParse(s);
    return v;
  }

  static bool _isPlausibleAmount(double v) {
    // Company-car till slips: ignore zero and absurd outliers
    return v > 0 && v < 500000;
  }

  // ── Date ─────────────────────────────────────────────────────────────────

  static DateTime? _extractDate(List<String> lines, DateTime now) {
    final earliest = DateTime(now.year - 1, now.month, now.day);
    final latest = DateTime(now.year, now.month, now.day);
    DateTime? best;
    // Prefer dates in the first half of the slip (header)
    final limit = (lines.length / 2).ceil().clamp(1, lines.length);
    for (var pass = 0; pass < 2; pass++) {
      final from = pass == 0 ? 0 : limit;
      final to = pass == 0 ? limit : lines.length;
      for (var i = from; i < to; i++) {
        final d = _dateInLine(lines[i]);
        if (d == null) continue;
        if (d.isBefore(earliest) || d.isAfter(latest)) continue;
        best = d;
        if (pass == 0) return best;
      }
      if (best != null) return best;
    }
    return best;
  }

  static DateTime? _dateInLine(String line) {
    final iso = _isoDate.firstMatch(line);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = int.parse(iso.group(2)!);
      final d = int.parse(iso.group(3)!);
      return _tryDate(y, m, d);
    }
    final sa = _saDate.firstMatch(line);
    if (sa != null) {
      final a = int.parse(sa.group(1)!);
      final b = int.parse(sa.group(2)!);
      var y = int.parse(sa.group(3)!);
      if (y < 100) y += 2000;
      // SA till slips are almost always DD/MM/YYYY
      return _tryDate(y, b, a);
    }
    return null;
  }

  static DateTime? _tryDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  // ── Description / merchant ───────────────────────────────────────────────

  static String? _extractDescription(List<String> lines) {
    final known = [
      'ENGEN',
      'SHELL',
      'BP',
      'SASOL',
      'CALTEX',
      'TOTAL',
      'ASTRON',
      'PUMA',
      'MAKEPEACE',
      'GARAGE',
      'MOTORS',
      'SERVICE STATION',
      'FILLING STATION',
      'TOLL',
      'PARKING',
      'CAR WASH',
    ];

    for (final line in lines.take(8)) {
      final upper = line.toUpperCase();
      for (final brand in known) {
        if (upper.contains(brand) && !_noiseLine.hasMatch(line)) {
          return _cleanDesc(line);
        }
      }
    }

    for (final line in lines.take(6)) {
      if (line.length < 3) continue;
      if (_noiseLine.hasMatch(line)) continue;
      if (_saDate.hasMatch(line) || _isoDate.hasMatch(line)) continue;
      if (_amountToken.hasMatch(line) && line.length < 12) continue;
      if (RegExp(r'^\d+$').hasMatch(line)) continue;
      return _cleanDesc(line);
    }
    return null;
  }

  static String _cleanDesc(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 80) return t;
    return '${t.substring(0, 77)}...';
  }

  // ── Category ─────────────────────────────────────────────────────────────

  static String? _suggestCategory(String rawText, List<String> categories) {
    if (categories.isEmpty) return null;
    final lower = rawText.toLowerCase();
    final byLower = {
      for (final c in categories) c.toLowerCase().trim(): c,
    };

    for (final entry in _categoryKeywords.entries) {
      final hit = entry.value.any((kw) => lower.contains(kw));
      if (!hit) continue;
      final prefs = _categoryLabelPrefs[entry.key] ?? [];
      for (final pref in prefs) {
        final match = byLower[pref.toLowerCase()];
        if (match != null) return match;
      }
      // Fuzzy: any settings label containing the group key
      for (final c in categories) {
        final cl = c.toLowerCase();
        if (cl.contains(entry.key) ||
            (entry.key == 'fuel' &&
                (cl.contains('petrol') || cl.contains('diesel'))) ||
            (entry.key == 'wash' && cl.contains('wash')) ||
            (entry.key == 'maintenance' && cl.contains('service'))) {
          return c;
        }
      }
    }
    return null;
  }
}
