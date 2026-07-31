import 'dart:io' show Directory, File;

import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/press_manual_entry.dart';
import '../models/press_manual_pdf_source.dart';

/// Downloads OEM PDFs into **app-private** cache only (mobile) or session
/// memory (web).
///
/// Security rules of the road:
/// - Never writes to public Downloads / MediaStore
/// - Never opens a public download URL in a browser
/// - Does not expose share / export APIs
/// - Mobile: files under application support (not user-visible gallery)
/// - Web: authenticated [Reference.getData] only — in-app [PdfViewer.data]
class PressManualCacheService {
  PressManualCacheService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Session cache for Flutter web (origin-bound; not a public CDN page).
  final Map<String, Uint8List> _webMemory = {};

  /// Default max download size when catalog has no [PressManualEntry.sizeBytes]
  /// (full Badenia handbook is ~46 MB).
  static const int defaultMaxBytes = 55 * 1024 * 1024;

  Future<Directory> _cacheDir() async {
    // Application support is private to the app on Android/iOS.
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/press_manuals_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> localFileFor(PressManualEntry entry) async {
    if (!entry.isRemotePdf || entry.storagePath == null) {
      throw StateError('Not a remote PDF: ${entry.id}');
    }
    final dir = await _cacheDir();
    // Flat name: id only (no path traversal from storagePath).
    final safe = entry.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}/$safe.pdf');
  }

  int _maxDownloadBytes(PressManualEntry entry) {
    final expected = entry.sizeBytes;
    if (expected == null || expected <= 0) return defaultMaxBytes;
    // Headroom for minor size drift vs catalog.
    final withMargin = (expected * 1.15).ceil() + (256 * 1024);
    return withMargin.clamp(expected, defaultMaxBytes * 2);
  }

  Future<bool> isCached(PressManualEntry entry) async {
    if (!entry.isRemotePdf) return true;
    if (kIsWeb) {
      final bytes = _webMemory[entry.id];
      if (bytes == null || bytes.isEmpty) return false;
      if (entry.sizeBytes != null &&
          bytes.length < (entry.sizeBytes! * 0.5).floor()) {
        return false;
      }
      return true;
    }
    final file = await localFileFor(entry);
    if (!await file.exists()) return false;
    final len = await file.length();
    if (entry.sizeBytes != null && len < (entry.sizeBytes! * 0.5).floor()) {
      // Truncated download — treat as missing.
      return false;
    }
    return true;
  }

  /// Ensure PDF is available for the in-app viewer.
  ///
  /// Mobile: downloads to private app support dir via [Reference.writeToFile].
  /// Web: authenticated [Reference.getData] into session memory (no public URL).
  ///
  /// [onProgress] is 0.0–1.0 when the SDK reports progress (mobile writeToFile).
  /// On web, progress may jump 0 → 1 when the download completes.
  Future<PressManualPdfSource> ensureLocal(
    PressManualEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    if (!entry.isRemotePdf || entry.storagePath == null) {
      throw StateError('Not a remote PDF: ${entry.id}');
    }

    if (kIsWeb) {
      return _ensureWeb(entry, onProgress: onProgress);
    }
    return _ensureMobileFile(entry, onProgress: onProgress);
  }

  Future<PressManualPdfSource> _ensureWeb(
    PressManualEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    final cached = _webMemory[entry.id];
    if (cached != null && await isCached(entry)) {
      if (entry.sha256 != null) {
        final ok = _sha256BytesMatches(cached, entry.sha256!);
        if (ok) {
          onProgress?.call(1);
          return PressManualPdfSource.memory(
            sourceName: entry.id,
            bytes: cached,
          );
        }
        _webMemory.remove(entry.id);
      } else {
        onProgress?.call(1);
        return PressManualPdfSource.memory(
          sourceName: entry.id,
          bytes: cached,
        );
      }
    }

    onProgress?.call(0);
    final ref = _storage.ref(entry.storagePath!);
    final data = await ref.getData(_maxDownloadBytes(entry));
    if (data == null || data.isEmpty) {
      throw StateError('Empty download for ${entry.id}');
    }
    if (entry.sha256 != null && !_sha256BytesMatches(data, entry.sha256!)) {
      throw StateError(
        'Downloaded file failed integrity check for ${entry.id}. '
        'Re-upload the manual or clear cache.',
      );
    }
    _webMemory[entry.id] = data;
    onProgress?.call(1);
    return PressManualPdfSource.memory(sourceName: entry.id, bytes: data);
  }

  Future<PressManualPdfSource> _ensureMobileFile(
    PressManualEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    final file = await localFileFor(entry);
    if (await isCached(entry)) {
      if (entry.sha256 != null) {
        final ok = await _sha256FileMatches(file, entry.sha256!);
        if (ok) {
          onProgress?.call(1);
          return PressManualPdfSource.file(
            sourceName: entry.id,
            path: file.path,
          );
        }
        // Corrupt / replaced — re-download.
        try {
          await file.delete();
        } catch (_) {}
      } else {
        onProgress?.call(1);
        return PressManualPdfSource.file(
          sourceName: entry.id,
          path: file.path,
        );
      }
    }

    final ref = _storage.ref(entry.storagePath!);
    // writeToFile keeps bytes in app-private path only.
    final task = ref.writeToFile(file);
    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        if (total > 0) {
          onProgress(snap.bytesTransferred / total);
        }
      });
    }
    await task;

    if (entry.sha256 != null) {
      final ok = await _sha256FileMatches(file, entry.sha256!);
      if (!ok) {
        try {
          await file.delete();
        } catch (_) {}
        throw StateError(
          'Downloaded file failed integrity check for ${entry.id}. '
          'Re-upload the manual or clear cache.',
        );
      }
    }
    return PressManualPdfSource.file(sourceName: entry.id, path: file.path);
  }

  Future<void> removeLocal(PressManualEntry entry) async {
    if (!entry.isRemotePdf) return;
    if (kIsWeb) {
      _webMemory.remove(entry.id);
      return;
    }
    final file = await localFileFor(entry);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> clearAll() async {
    _webMemory.clear();
    if (kIsWeb) return;
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  bool _sha256BytesMatches(Uint8List bytes, String expectedHex) {
    try {
      final digest = sha256.convert(bytes);
      return digest.toString().toLowerCase() == expectedHex.toLowerCase();
    } catch (e) {
      debugPrint('PressManualCacheService sha256 bytes: $e');
      return false;
    }
  }

  Future<bool> _sha256FileMatches(File file, String expectedHex) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == expectedHex.toLowerCase();
    } catch (e) {
      debugPrint('PressManualCacheService sha256 file: $e');
      return false;
    }
  }
}
