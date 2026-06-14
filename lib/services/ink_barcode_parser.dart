/// Parses the barcodes on a Siegwerk IBC into the fields the receive flow needs.
///
/// PURE DART — no Flutter — so it is unit-testable. Ported from the operator's
/// PowerApps scan logic, with the confirmed label rules:
///   - IBC number  : SSCC barcode ("00"+18-digit, or a bare 18-digit NVE) -> right 8.
///                   (also accepts a legacy "&..." code -> right 8.)
///   - Weight (kg) : GS1-128 "(3100)" net-weight (6 digits, no implied decimals);
///                   or a legacy "#..." code -> right 6 / 100.
///   - Charge/batch: GS1-128 "(10)" lot, between the GTIN and "3100".
///   - Colour      : a product barcode whose right-9 matches a known article no.
///   - The top GS1 gives weight+charge; the SSCC gives the IBC number; the three
///     separate codes give IBC/colour/weight. Point at whatever is readable —
///     every scanned code is merged, so partial scans still fill what they can.
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

/// Siegwerk article number (right-9 of the product barcode) -> CTP ink colour.
/// Extend here if a colour's article number changes.
const Map<String, String> kInkArticleColours = {
  '123024622': 'Yellow',
  '128049871': 'Red',
  '121218796': 'Blue',
  '129097382': 'Black',
};

// Strip control chars (GS1 FNC1 / group separators) + spaces the scanner may
// include; keeps printable chars like '&', '#', and digits.
String _clean(String s) =>
    s.replaceAll(RegExp(r'[^\x21-\x7e]'), '').trim();

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

  // --- Colour (article right-9) ---
  for (final c in codes) {
    if (c.length >= 9) {
      final colourName = kInkArticleColours[c.substring(c.length - 9)];
      if (colourName != null) {
        colour = colourName;
        break;
      }
    }
  }

  // --- Weight + charge ---
  for (final c in codes) {
    if (c.startsWith('#') && c.length >= 7) {
      weight = (double.tryParse(c.substring(c.length - 6)) ?? 0) / 100;
      break;
    }
  }
  if (weight == null) {
    for (final c in codes) {
      if (c.startsWith('01') && c.contains('3100')) {
        final pos = c.indexOf('3100');
        final end = (pos + 4 + 6 <= c.length) ? pos + 4 + 6 : c.length;
        final wStr = c.substring(pos + 4, end);
        weight = double.tryParse(wStr);
        truncated = wStr.length < 6; // partial / damaged scan
        // Charge (AI 10) sits between the GTIN (01 + 14 digits, then "10") and 3100.
        if (c.length >= 18 && c.substring(16).startsWith('10') && pos >= 18) {
          charge = c.substring(18, pos);
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
