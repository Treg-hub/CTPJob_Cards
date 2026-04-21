import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for checking and handling app updates
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _lastCheckKey = 'last_update_check';
  static const Duration _checkInterval = Duration(days: 1);

  /// Check for updates and show dialog if needed
  /// Call this after successful login, only on mobile platforms
  Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return; // Skip on web

    try {
      // Check if we already checked today
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastCheck != null && (now - lastCheck) < _checkInterval.inMilliseconds) {
        debugPrint('Update check skipped - checked recently');
        return;
      }

      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = packageInfo.buildNumber;

      debugPrint('Current app version: $currentVersion+$currentBuild');

      // Fetch latest version from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('latest_version')
          .get();

      if (!doc.exists) {
        debugPrint('No update config found in Firestore');
        return;
      }

      final data = doc.data()!;
      final latestVersion = data['version'] as String?;
      final latestBuild = data['buildNumber'] as String?;
      final downloadUrl = data['downloadUrl'] as String?;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final releaseNotes = data['releaseNotes'] as String?;

      if (latestVersion == null || downloadUrl == null) {
        debugPrint('Incomplete update config');
        return;
      }

      // Compare versions
      if (!_isNewerVersion(currentVersion, latestVersion, currentBuild, latestBuild)) {
        debugPrint('App is up to date');
        // Still update last check time
        await prefs.setInt(_lastCheckKey, now);
        return;
      }

      debugPrint('New version available: $latestVersion+$latestBuild');

      // Update last check time
      await prefs.setInt(_lastCheckKey, now);

      // Show update dialog
      if (context.mounted) {
        await _showUpdateDialog(
          context,
          latestVersion,
          releaseNotes,
          downloadUrl,
          forceUpdate,
        );
      }

    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  /// Compare versions using semantic versioning
  bool _isNewerVersion(String currentVersion, String latestVersion, String currentBuild, String? latestBuild) {
    try {
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      final latestParts = latestVersion.split('.').map(int.parse).toList();

      // Compare major.minor.patch
      for (int i = 0; i < 3; i++) {
        final current = currentParts.length > i ? currentParts[i] : 0;
        final latest = latestParts.length > i ? latestParts[i] : 0;

        if (latest > current) return true;
        if (latest < current) return false;
      }

      // If versions are equal, compare build numbers
      if (latestBuild != null) {
        final currentBuildNum = int.tryParse(currentBuild) ?? 0;
        final latestBuildNum = int.tryParse(latestBuild) ?? 0;
        return latestBuildNum > currentBuildNum;
      }

      return false;
    } catch (e) {
      debugPrint('Error comparing versions: $e');
      return false;
    }
  }

  /// Show update dialog
  Future<void> _showUpdateDialog(
    BuildContext context,
    String version,
    String? releaseNotes,
    String downloadUrl,
    bool forceUpdate,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) => AlertDialog(
        title: Text('Update Available (v$version)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                const Text(
                  'What\'s New:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(releaseNotes),
                const SizedBox(height: 16),
              ],
              const Text(
                'A new version of the app is available. Please update to continue using the latest features.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          ElevatedButton(
            onPressed: () async {
              try {
                final uri = Uri.parse(downloadUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unable to open download link')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error opening download: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C42),
              foregroundColor: Colors.black,
            ),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}