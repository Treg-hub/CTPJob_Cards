import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Dual-write / path helpers for Storage region migration (Phase 3).
///
/// - [primary]: `ctp-job-cards-media-as1` (africa-south1)
/// - [legacy]: `ctp-job-cards.firebasestorage.app` (us-central1)
///
/// Uploads write both when [dualWrite] is true. Download URLs prefer primary.
/// See monorepo `docs/Storage_Region_Migration.md`.
class AppStorage {
  AppStorage._();

  static const String primaryBucket = 'ctp-job-cards-media-as1';
  static const String legacyBucket = 'ctp-job-cards.firebasestorage.app';

  /// Set false only after Phase 7 (AS1-only writes).
  static bool dualWrite = true;

  static FirebaseStorage get primary =>
      FirebaseStorage.instanceFor(bucket: primaryBucket);

  static FirebaseStorage get legacy =>
      FirebaseStorage.instanceFor(bucket: legacyBucket);

  /// Default instance (still project default / US until firebase_options cutover).
  static FirebaseStorage get projectDefault => FirebaseStorage.instance;

  static Future<String> putFile(
    String path,
    File file, {
    SettableMetadata? metadata,
  }) async {
    String? primaryUrl;
    String? legacyUrl;
    Object? primaryErr;
    Object? legacyErr;

    try {
      final task = await primary.ref(path).putFile(file, metadata);
      primaryUrl = await task.ref.getDownloadURL();
    } catch (e, st) {
      primaryErr = e;
      debugPrint('AppStorage primary putFile failed $path: $e\n$st');
    }

    if (dualWrite) {
      try {
        final task = await legacy.ref(path).putFile(file, metadata);
        legacyUrl = await task.ref.getDownloadURL();
      } catch (e, st) {
        legacyErr = e;
        debugPrint('AppStorage legacy putFile failed $path: $e\n$st');
      }
    }

    if (primaryUrl != null) return primaryUrl;
    if (legacyUrl != null) return legacyUrl;
    throw primaryErr ?? legacyErr ?? StateError('Upload failed for $path');
  }

  static Future<String> putData(
    String path,
    Uint8List data, {
    SettableMetadata? metadata,
  }) async {
    String? primaryUrl;
    String? legacyUrl;
    Object? primaryErr;
    Object? legacyErr;

    try {
      final task = await primary.ref(path).putData(data, metadata);
      primaryUrl = await task.ref.getDownloadURL();
    } catch (e, st) {
      primaryErr = e;
      debugPrint('AppStorage primary putData failed $path: $e\n$st');
    }

    if (dualWrite) {
      try {
        final task = await legacy.ref(path).putData(data, metadata);
        legacyUrl = await task.ref.getDownloadURL();
      } catch (e, st) {
        legacyErr = e;
        debugPrint('AppStorage legacy putData failed $path: $e\n$st');
      }
    }

    if (primaryUrl != null) return primaryUrl;
    if (legacyUrl != null) return legacyUrl;
    throw primaryErr ?? legacyErr ?? StateError('Upload failed for $path');
  }

  /// Upload without needing the download URL (callers that only store path).
  static Future<void> putFilePathOnly(
    String path,
    File file, {
    SettableMetadata? metadata,
  }) async {
    await putFile(path, file, metadata: metadata);
  }

  static Future<String> getDownloadUrl(String path) async {
    try {
      return await primary.ref(path).getDownloadURL();
    } catch (_) {
      return await legacy.ref(path).getDownloadURL();
    }
  }
}
