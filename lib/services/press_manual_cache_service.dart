import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/press_manual_entry.dart';

/// Downloads OEM PDFs into **app-private** cache only.
///
/// Security rules of the road:
/// - Never writes to public Downloads / MediaStore
/// - Never opens a public download URL in a browser
/// - Does not expose share / export APIs
/// - Files live under application support (not user-visible gallery)
class PressManualCacheService {
  PressManualCacheService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

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

  Future<bool> isCached(PressManualEntry entry) async {
    if (!entry.isRemotePdf) return true;
    final file = await localFileFor(entry);
    if (!await file.exists()) return false;
    final len = await file.length();
    if (entry.sizeBytes != null && len < (entry.sizeBytes! * 0.5).floor()) {
      // Truncated download — treat as missing.
      return false;
    }
    return true;
  }

  /// Ensure PDF is on device. Downloads from Storage if needed.
  /// [onProgress] is 0.0–1.0 when the SDK reports progress.
  Future<File> ensureLocal(
    PressManualEntry entry, {
    void Function(double progress)? onProgress,
  }) async {
    if (!entry.isRemotePdf || entry.storagePath == null) {
      throw StateError('Not a remote PDF: ${entry.id}');
    }
    final file = await localFileFor(entry);
    if (await isCached(entry)) {
      if (entry.sha256 != null) {
        final ok = await _sha256Matches(file, entry.sha256!);
        if (ok) return file;
        // Corrupt / replaced — re-download.
        try {
          await file.delete();
        } catch (_) {}
      } else {
        return file;
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
      final ok = await _sha256Matches(file, entry.sha256!);
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
    return file;
  }

  Future<void> removeLocal(PressManualEntry entry) async {
    if (!entry.isRemotePdf) return;
    final file = await localFileFor(entry);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> clearAll() async {
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> _sha256Matches(File file, String expectedHex) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == expectedHex.toLowerCase();
    } catch (e) {
      debugPrint('PressManualCacheService sha256: $e');
      return false;
    }
  }
}
