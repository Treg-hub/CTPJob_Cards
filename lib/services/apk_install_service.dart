import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads a release APK into app-private storage and hands it to the
/// Android package installer via a MethodChannel + FileProvider.
///
/// Not available on web. See plan: in-app APK install (sideload, not Play).
class ApkInstallService {
  static final ApkInstallService _instance = ApkInstallService._internal();
  factory ApkInstallService() => _instance;
  ApkInstallService._internal();

  static const MethodChannel _channel = MethodChannel('ctp/apk_install');

  HttpClient? _activeClient;
  bool _cancelled = false;

  /// Whether the OS currently allows this app to install packages.
  Future<bool> canInstallPackages() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (e) {
      debugPrint('ApkInstallService.canInstallPackages: $e');
      return false;
    }
  }

  /// Opens system Settings for "Install unknown apps" for this package.
  Future<void> openInstallPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } catch (e) {
      debugPrint('ApkInstallService.openInstallPermissionSettings: $e');
      rethrow;
    }
  }

  /// Streams [url] to app-private `updates/` and reports [onProgress]
  /// (receivedBytes, totalBytes-or-null).
  Future<File> downloadApk(
    String url, {
    String? fileNameHint,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (kIsWeb) {
      throw StateError('APK download is not available on web');
    }
    _cancelled = false;
    final dir = await _updatesDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Clear older downloads so storage does not accumulate.
    await _clearOldApks(dir);

    final safeName = _safeFileName(fileNameHint ?? 'ctp-job-cards-update.apk');
    final file = File('${dir.path}/$safeName');
    if (await file.exists()) {
      await file.delete();
    }

    final client = HttpClient();
    // Avoid transparent compression so Content-Length matches on-disk APK size
    // (gzip/deflate can make progress show a wrong "total", e.g. a tiny number).
    client.autoUncompress = false;
    _activeClient = client;
    try {
      final uri = Uri.parse(url);

      // Prefer HEAD Content-Length (Firebase Hosting / CDN) before streaming.
      int? total = await _probeContentLength(client, uri);

      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      if (_cancelled) {
        throw const ApkInstallException('Download cancelled');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApkInstallException(
          'Download failed (HTTP ${response.statusCode}). Ask an admin to check the update URL.',
        );
      }

      final fromGet = _contentLengthFromResponse(response);
      // Trust a positive GET length; else keep HEAD. Ignore tiny/wrong totals
      // (real release APKs are multi‑MB; a total of a few dozen bytes is noise).
      if (fromGet != null && fromGet >= 1024 * 1024) {
        total = fromGet;
      } else if (total == null || total < 1024 * 1024) {
        total = fromGet != null && fromGet >= 1024 * 1024 ? fromGet : null;
      }

      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          if (_cancelled) {
            throw const ApkInstallException('Download cancelled');
          }
          sink.add(chunk);
          received += chunk.length;
          // If server under-reported size, stop using total so UI shows
          // indeterminate + received-only instead of capping at e.g. "22 MB".
          var reportTotal = total;
          if (reportTotal != null && received > reportTotal) {
            reportTotal = null;
            total = null;
          }
          onProgress?.call(received, reportTotal);
        }
      } finally {
        await sink.close();
      }

      if (received == 0) {
        if (await file.exists()) await file.delete();
        throw const ApkInstallException('Download was empty');
      }
      // Final tick with real file size (authoritative for the status line).
      onProgress?.call(received, received);
      return file;
    } on ApkInstallException {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    } on SocketException {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      throw const ApkInstallException(
        'No network — check Wi‑Fi and try again.',
      );
    } catch (e) {
      if (e is ApkInstallException) rethrow;
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      throw ApkInstallException('Download failed: $e');
    } finally {
      client.close(force: true);
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
    }
  }

  void cancelDownload() {
    _cancelled = true;
    _activeClient?.close(force: true);
    _activeClient = null;
  }

  /// HEAD (or short probe) for Content-Length without downloading the body.
  static Future<int?> _probeContentLength(HttpClient client, Uri uri) async {
    try {
      final head = await client.headUrl(uri);
      head.followRedirects = true;
      head.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final res = await head.close();
      // Drain any body (some CDNs still send a tiny payload on HEAD).
      await res.drain<void>();
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return _contentLengthFromResponse(res);
    } catch (e) {
      debugPrint('ApkInstallService: HEAD size probe failed: $e');
      return null;
    }
  }

  static int? _contentLengthFromResponse(HttpClientResponse response) {
    if (response.contentLength >= 0) return response.contentLength;
    final raw = response.headers.value(HttpHeaders.contentLengthHeader);
    if (raw == null || raw.isEmpty) return null;
    final n = int.tryParse(raw.trim());
    if (n == null || n < 0) return null;
    return n;
  }

  /// When [expectedHex] is non-empty, require the file's SHA-256 to match
  /// (case-insensitive, optional `sha256:` prefix).
  Future<void> verifySha256(File file, String? expectedHex) async {
    final expected = _normalizeSha(expectedHex);
    if (expected == null) return;

    final digest = await sha256.bind(file.openRead()).first;
    final actual = digest.toString().toLowerCase();
    if (actual != expected) {
      try {
        await file.delete();
      } catch (_) {}
      throw const ApkInstallException(
        'Downloaded file failed integrity check. Try again, or open the browser download as a fallback.',
      );
    }
  }

  /// Hands [file] to the system package installer.
  Future<void> installApk(File file) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw const ApkInstallException('Install is only available on Android');
    }
    if (!await file.exists()) {
      throw const ApkInstallException('Update file is missing — download again');
    }
    try {
      await _channel.invokeMethod<void>('installApk', {
        'path': file.absolute.path,
      });
    } on PlatformException catch (e) {
      throw ApkInstallException(
        e.message?.isNotEmpty == true
            ? e.message!
            : 'Could not open the installer (${e.code})',
      );
    }
  }

  Future<Directory> _updatesDir() async {
    // Prefer app-specific external files (FileProvider external-files-path);
    // fall back to internal support dir (FileProvider files-path).
    Directory base;
    try {
      base = await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } catch (_) {
      base = await getApplicationSupportDirectory();
    }
    return Directory('${base.path}/updates');
  }

  Future<void> _clearOldApks(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('ApkInstallService: clear old apks: $e');
    }
  }

  static String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (cleaned.toLowerCase().endsWith('.apk')) return cleaned;
    return '$cleaned.apk';
  }

  static String? _normalizeSha(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.startsWith('sha256:')) s = s.substring(7).trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) return null;
    return s;
  }
}

class ApkInstallException implements Exception {
  final String message;
  const ApkInstallException(this.message);

  @override
  String toString() => message;
}
