import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hard version gate shown before login when this build is older than
/// `settings/app.minSupportedBuild`. Unlike the Remote Config force-update
/// dialog (which only fires on HomeScreen creation with a cooldown), this
/// blocks the app entirely — retiring a broken build is a one-field
/// Firestore edit.
class UpdateRequiredScreen extends StatelessWidget {
  final String downloadUrl;

  const UpdateRequiredScreen({super.key, required this.downloadUrl});

  Future<void> _openDownload(BuildContext context) async {
    try {
      await launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the download link.\n$downloadUrl')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 96, color: Color(0xFFFF8C42)),
                const SizedBox(height: 24),
                const Text(
                  'Update Required',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This version of CTP Job Cards is no longer supported.\n'
                  'Please install the latest version to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 32),
                if (downloadUrl.isNotEmpty)
                  Builder(
                    builder: (ctx) => ElevatedButton.icon(
                      onPressed: () => _openDownload(ctx),
                      icon: const Icon(Icons.download),
                      label: const Text('Update Now', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C42),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Ask your administrator for the new APK.',
                    style: TextStyle(fontSize: 14, color: Colors.white54),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
