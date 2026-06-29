/// SSCC / IBC number helpers — store full SSCC when known; display last 8.
class InkSscc {
  InkSscc._();

  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// Last 8 digits — operator-facing IBC number.
  static String displayNumber({String? sscc, required String ibcNumber}) {
    final d = sscc != null && sscc.isNotEmpty ? digitsOnly(sscc) : ibcNumber;
    return d.length >= 8 ? d.substring(d.length - 8) : d;
  }

  /// Firestore doc id: full SSCC digits when ≥18, else legacy short number.
  static String docId({String? sscc, required String ibcNumber}) {
    final full = sscc != null && sscc.isNotEmpty ? digitsOnly(sscc) : '';
    if (full.length >= 18) return full;
    return ibcNumber;
  }
}