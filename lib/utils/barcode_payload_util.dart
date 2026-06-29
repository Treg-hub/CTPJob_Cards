import 'dart:convert';
import 'dart:typed_data';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Prefix for binary barcode payloads stored as Firestore strings.
const String kBarcodeBase64Prefix = 'base64:';

/// Extracts a usable payload string from a [Barcode].
///
/// SA driver's licence PDF417 is RSA-encrypted binary — [Barcode.rawValue] is
/// often null on Android/iOS. Prefer [Barcode.rawDecodedBytes] in that case.
class BarcodePayloadUtil {
  BarcodePayloadUtil._();

  /// Returns a text or `base64:…` payload, or null if nothing usable was found.
  ///
  /// Set [preferBinary] for SA driver's licence PDF417 — scanners often expose a
  /// useless Latin-1 [Barcode.rawValue] while the decryptable payload is only in
  /// [Barcode.rawDecodedBytes]. Scan Tester worked because it never preferred
  /// [rawValue] when bytes looked like an encrypted licence.
  static String? extractPayload(
    Barcode barcode, {
    bool preferBinary = false,
  }) {
    final bytes = extractRawBytes(barcode);
    final raw = barcode.rawValue?.trim();

    if (bytes != null &&
        bytes.isNotEmpty &&
        (preferBinary || isLikelyEncryptedDriverLicence(bytes))) {
      return encodeBytesPayload(bytes);
    }

    if (raw != null && raw.isNotEmpty && !_looksLikeBinaryGarbage(raw)) {
      return raw;
    }

    if (bytes != null && bytes.isNotEmpty) {
      return encodeBytesPayload(bytes);
    }

    return null;
  }

  /// Encrypted SA driver's licence PDF417 is 720 bytes; decrypted payloads ~684.
  static bool isLikelyEncryptedDriverLicence(Uint8List bytes) {
    final len = bytes.length;
    return len >= 600 && len <= 800;
  }

  /// Raw barcode bytes from [Barcode], when the scanner exposes them.
  static Uint8List? extractRawBytes(Barcode barcode) {
    final decoded = barcode.rawDecodedBytes;
    if (decoded != null) {
      return switch (decoded) {
        DecodedVisionBarcodeBytes(:final rawBytes) => rawBytes,
        DecodedBarcodeBytes(:final bytes) => bytes,
      };
    }

    // ignore: deprecated_member_use
    final legacy = barcode.rawBytes;
    if (legacy != null && legacy.isNotEmpty) return legacy;

    return null;
  }

  /// Encodes bytes for storage / parser input (`base64:…`).
  static String encodeBytesPayload(Uint8List bytes) {
    return '$kBarcodeBase64Prefix${base64Encode(bytes)}';
  }

  /// Decodes a payload that may be plain text or `base64:…`.
  static Uint8List? decodeBytesPayload(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith(kBarcodeBase64Prefix)) return null;
    try {
      return base64Decode(trimmed.substring(kBarcodeBase64Prefix.length));
    } catch (_) {
      return null;
    }
  }

  /// Human-readable summary for UI (truncated base64 for binary captures).
  static String displayPayload(String payload) {
    if (!payload.startsWith(kBarcodeBase64Prefix)) return payload;
    final bytes = decodeBytesPayload(payload);
    final byteCount = bytes?.length ?? 0;
    final b64 = payload.substring(kBarcodeBase64Prefix.length);
    final preview = b64.length > 48 ? '${b64.substring(0, 48)}…' : b64;
    return 'Encrypted barcode ($byteCount bytes): $preview';
  }

  static bool isBinaryPayload(String payload) {
    return payload.trim().startsWith(kBarcodeBase64Prefix);
  }

  /// Latin-1 decoded [rawValue] with many non-printable chars — not useful text.
  static bool _looksLikeBinaryGarbage(String raw) {
    if (raw.startsWith(kBarcodeBase64Prefix)) return false;
    var nonPrintable = 0;
    for (final codeUnit in raw.codeUnits) {
      if (codeUnit < 0x20 || codeUnit > 0x7e) nonPrintable++;
    }
    return nonPrintable > raw.length ~/ 4;
  }
}