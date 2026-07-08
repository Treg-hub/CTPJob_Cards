import 'package:flutter/material.dart';

import 'update_available_screen.dart';

/// Hard version gate shown before login when this build is older than
/// `settings/app.minSupportedBuild`. Unlike the Remote Config force-update
/// prompt (which only fires after Home is reachable with a cooldown), this
/// blocks the app entirely — retiring a broken build is a one-field
/// Firestore edit.
///
/// Uses the same in-app download + install pipeline as soft updates.
class UpdateRequiredScreen extends StatelessWidget {
  final String downloadUrl;

  const UpdateRequiredScreen({super.key, required this.downloadUrl});

  @override
  Widget build(BuildContext context) {
    return UpdateAvailableScreen(
      version: 'latest',
      downloadUrl: downloadUrl,
      releaseNotes:
          'This version of CTP Job Cards is no longer supported.\n'
          'Please install the latest version to continue.',
      forceUpdate: true,
      standalone: true,
    );
  }
}
