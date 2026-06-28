import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/fleet_service.dart';
import 'fleet_constants.dart';

/// Pick one compressed fleet photo (1024×1024, q70 via [FleetService]).
Future<String?> pickFleetCompressedPhoto(
  BuildContext context,
  FleetService service, {
  required int currentCount,
  int maxPhotos = kFleetMaxPhotos,
}) async {
  if (currentCount >= maxPhotos) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Maximum $maxPhotos photos reached.')),
    );
    return null;
  }
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return service.pickAndCompressPhoto(source);
}