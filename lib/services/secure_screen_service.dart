import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// Best-effort screen hardening for confidential in-app content (press manuals).
///
/// Android: [FLAG_SECURE] via MethodChannel (blocks screenshots / recents preview
/// on most devices). iOS / web: no-op with log (cannot fully prevent capture).
///
/// This is not DRM. Determined attackers with rooted devices or cameras can still
/// copy content. Product rule: no share/export/print/external open in the UI.
class SecureScreenService {
  SecureScreenService._();

  static const _channel = MethodChannel('ctp/secure_screen');
  static int _secureDepth = 0;

  /// Enter a secure viewing context (pair with [exitSecure] in dispose).
  static Future<void> enterSecure() async {
    _secureDepth++;
    if (_secureDepth != 1) return;
    await _setSecure(true);
  }

  /// Leave a secure viewing context.
  static Future<void> exitSecure() async {
    if (_secureDepth == 0) return;
    _secureDepth--;
    if (_secureDepth != 0) return;
    await _setSecure(false);
  }

  static Future<void> _setSecure(bool secure) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('setSecure', {'secure': secure});
      }
    } catch (e) {
      debugPrint('SecureScreenService: $e');
    }
  }
}
