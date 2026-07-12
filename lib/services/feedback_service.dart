import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../utils/persona_audit.dart';

/// Photo helpers for the in-app feedback loop.
///
/// Mirrors Fleet/Waste pick → compress (1024×1024, q70) → Storage upload.
/// Path: `feedback/{feedbackId}/photos/{uuid}.jpg`.
///
/// Submitters cannot update the parent `feedback` doc (admin triage only),
/// so callers must mint a doc id, upload, then create with `photoUrls` in
/// one write.
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const int maxPhotosPerMessage = 3;

  void _guardWrite() => assertPersonaSubmitAllowed();

  /// Camera or gallery → compressed JPEG temp path, or null if cancelled.
  Future<String?> pickAndCompressPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return null;

    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/${const Uuid().v4()}.jpg';

    final compressed = await FlutterImageCompress.compressAndGetFile(
      picked.path,
      outPath,
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
      rotate: 0,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    return compressed?.path;
  }

  /// Uploads compressed local files; returns download URLs in order.
  Future<List<String>> uploadPhotos({
    required String feedbackId,
    required List<String> localPaths,
  }) async {
    _guardWrite();
    if (localPaths.isEmpty) return const [];
    final urls = <String>[];
    for (final path in localPaths) {
      final file = File(path);
      if (!file.existsSync()) {
        throw Exception('Photo file was cleaned up before upload — please re-add it');
      }
      final fileName = '${const Uuid().v4()}.jpg';
      final ref = _storage.ref('feedback/$feedbackId/photos/$fileName');
      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await task.ref.getDownloadURL());
    }
    return urls;
  }
}
