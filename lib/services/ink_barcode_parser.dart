/// Parses the barcodes on a Siegwerk IBC into the fields the receive flow needs.
///
/// PURE DART — no Flutter — so it is unit-testable. Ported from the operator's
/// PowerApps scan logic, with the confirmed label rules:
///   - IBC number  : SSCC barcode ("00"+18-digit, or a bare 18-digit NVE) -> right 8.
///                   (also accepts a legacy "&..." code -> right 8.)
///   - Weight (kg) : GS1-128 "(31XX)" net-weight AI (3100=0dp…3105=5dp), 6 digits;
///                   or a legacy "#..." code -> right 6 / 100.
///   - Charge/batch: GS1-128 "(10)" lot, between the GTIN and the weight AI.
///   - Colour      : GTIN (right-14 after AI "01") looked up in [kInkGtinColours];
///                   or a legacy product barcode whose right-9 matches [kInkArticleColours].
///   - The top GS1 gives weight+charge+colour; the SSCC gives the IBC number; the three
///     separate codes give IBC/colour/weight. Point at whatever is readable —
///     every scanned code is merged, so partial scans still fill what they can.
///   - Both raw scanner output (FNC1 as control chars) and parenthesised
///     human-readable output (some scanners emit "(01)...(10)...") are handled.
class IbcScanResult {
  const IbcScanResult({
    this.ibcNumber,
    this.colour,
    this.weightKg,
    this.charge,
    this.weightTruncated = false,
  });

  final String? ibcNumber;
  final String? colour; // 'Yellow' | 'Red' | 'Blue' | 'Black'
  final double? weightKg;
  final String? charge;
  final bool weightTruncated;

  bool get hasAnything =>
      ibcNumber != null || colour != null || weightKg != null;
  bool get isComplete => ibcNumber != null && colour != null && weightKg != null;

  /// Combines two results, preferring already-populated fields.
  IbcScanResult merge(IbcScanResult o) => IbcScanResult(
        ibcNumber: ibcNumber ?? o.ibcNumber,
        colour: colour ?? o.colour,
        weightKg: weightKg ?? o.weightKg,
        charge: charge ?? o.charge,
        weightTruncated: weightTruncated || o.weightTruncated,
      );
}

/// Siegwerk GTIN (14-digit product code from AI-01 in GS1-128) → CTP ink colour.
///
/// Add one entry per confirmed physical label. To find the GTIN for a new colour,
/// scan the GS1-128 barcode and read the 14 digits after "(01)" on the label.
const Map<String, String> kInkGtinColours = {
  '04045647007179': 'Yellow',
  '04045647007407': 'Red',
  '04045648163515': 'Blue',
  // TODO: add Black GTIN once confirmed from physical label
};

/// Siegwerk article number (right-9 of a standalone legacy product barcode) → colour.
/// Used for the three-code legacy label format (not the modern GS1-128 combined label).
const Map<String, String> kInkArticleColours = {
  '123024622': 'Yellow',
  '128049871': 'Red',
  '121218796': 'Blue',
  '129097382': 'Black',
};

// Strip non-printable chars (FNC1 / group separators that scanners may inject) AND
// GS1 human-readable parentheses that some scanners include in rawValue
// (e.g. "(01)04045647007179(10)0014836440(3100)000940").
// Spaces (0x20) are also stripped since they appear in SSCC human-readable text.
// After this step both the raw and parenthesised scanner outputs are identical.
String _clean(String s) => s
    .replaceAll(RegExp(r'[^\x21-\x7e]'), '') // strip non-printable
    .replaceAll('(', '') // strip GS1 human-readable parens
    .replaceAll(')', '')
    .trim();

// Simple integer power of 10 (avoids importing dart:math for small exponents).
double _pow10(int exp) {
  double r = 1;
  for (int i = 0; i < exp; i++) {
    r *= 10;
  }
  return r;
}

IbcScanResult parseIbcBarcodes(List<String> rawCodes) {
  final codes = rawCodes.map(_clean).where((c) => c.isNotEmpty).toList();

  String? ibc;
  String? colour;
  String? charge;
  double? weight;
  var truncated = false;

  // --- IBC number ---
  for (final c in codes) {
    if (c.startsWith('&') && c.length >= 9) {
      ibc = c.substring(c.length - 8);
      break;
    }
  }
  if (ibc == null) {
    for (final c in codes) {
      if (c.startsWith('01')) continue; // GS1 product code, not an SSCC
      final digits = c.replaceAll(RegExp(r'\D'), '');
      final isSscc = (c.startsWith('00') && digits.length == 20) ||
          digits.length == 18; // bare NVE
      if (isSscc && digits.length >= 8) {
        ibc = digits.substring(digits.length - 8);
        break;
      }
    }
  }

  // --- Colour ---
  // 1. GS1-128: extract the GTIN from AI-01 (2-char AI + 14-char GTIN = positions 0..15)
  //    and look it up in the known GTIN→colour table.
  for (final c in codes) {
    if (c.startsWith('01') && c.length >= 16) {
      final gtin = c.substring(2, 16);
      final colourFromGtin = kInkGtinColours[gtin];
      if (colourFromGtin != null) {
        colour = colourFromGtin;
        break;
      }
    }
  }
  // 2. Legacy: right-9 of a standalone product barcode matches the article number table.
  if (colour == null) {
    for (final c in codes) {
      if (c.length >= 9) {
        final colourName = kInkArticleColours[c.substring(c.length - 9)];
        if (colourName != null) {
          colour = colourName;
          break;
        }
      }
    }
  }

  // --- Weight + charge ---
  // Legacy "#NNNNNN" format: right-6 divided by 100.
  for (final c in codes) {
    if (c.startsWith('#') && c.length >= 7) {
      weight = (double.tryParse(c.substring(c.length - 6)) ?? 0) / 100;
      break;
    }
  }
  // GS1-128 AI 31XX:  3100=0 decimal places, 3101=1dp, …, 3105=5dp.
  // The value field is always 6 digits.  weight_kg = raw_value / 10^decimals.
  if (weight == null) {
    for (final c in codes) {
      if (!c.startsWith('01')) continue;
      // Regex finds the first "31" + two-digit decimal indicator + up to 6 digits.
      final match = RegExp(r'31(0[0-5])(\d{1,6})').firstMatch(c);
      if (match != null && match.start >= 16) {
        // start >= 16 ensures we are past the GTIN, not matching inside it.
        final decimals = int.parse(match.group(1)!);
        final wStr = match.group(2)!;
        final rawVal = double.tryParse(wStr);
        if (rawVal != null) {
          weight = rawVal / _pow10(decimals);
          truncated = wStr.length < 6;
        }
        // Charge (AI 10) sits between the GTIN end (pos 16) and the weight AI start.
        final aiPos = match.start;
        if (c.length >= 18 && c.substring(16, 18) == '10' && aiPos >= 18) {
          charge = c.substring(18, aiPos);
        }
        break;
      }
    }
  }

  return IbcScanResult(
    ibcNumber: ibc,
    colour: colour,
    weightKg: weight,
    charge: charge,
    weightTruncated: truncated,
  );
}

/// Parses + merges all codes currently in view (so multi-barcode scans combine).
IbcScanResult parseIbcBarcodeSet(Iterable<String> codes) =>
    parseIbcBarcodes(codes.toList());
