import 'dart:async';
import 'package:firebase_remote_config/firebase_remote_config.dart';
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
  static const Duration _checkInterval = Duration(hours: 6);

  /// Normal check (respects 6h cooldown)
  Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastCheck != null && (now - lastCheck) < _checkInterval.inMilliseconds) {
        debugPrint('Update check skipped - checked recently');
        return;
      }

      await _performUpdateCheck(context, prefs, now);
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  /// Force immediate update check (ignores cooldown)
  Future<void> forceCheckForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Clear last check so it always runs
      await prefs.remove(_lastCheckKey);

      debugPrint('Forcing immediate update check...');
      await _performUpdateCheck(context, prefs, now);
    } catch (e) {
      debugPrint('Error forcing update check: $e');
    }
  }

  /// Internal method that does the actual check
  Future<void> _performUpdateCheck(BuildContext context, SharedPreferences prefs, int now) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = packageInfo.buildNumber;

      debugPrint('Current app version: $currentVersion+$currentBuild');

      await FirebaseRemoteConfig.instance.fetchAndActivate();

      final latestVersion = FirebaseRemoteConfig.instance.getString('latest_version');
      final latestBuild = FirebaseRemoteConfig.instance.getString('latest_build');
      final downloadUrl = FirebaseRemoteConfig.instance.getString('download_url');
      final forceUpdate = FirebaseRemoteConfig.instance.getBool('force_update');
      final releaseNotes = FirebaseRemoteConfig.instance.getString('release_notes');

      if (latestVersion.isEmpty || downloadUrl.isEmpty) {
        debugPrint('Incomplete update config');
        return;
      }

      if (!_isNewerVersion(currentVersion, latestVersion, currentBuild, latestBuild)) {
        debugPrint('App is up to date');
        await prefs.setInt(_lastCheckKey, now);
        return;
      }

      debugPrint('New version available: $latestVersion+$latestBuild');
      await prefs.setInt(_lastCheckKey, now);

      if (context.mounted) {
        await _showUpdateDialog(context, latestVersion, releaseNotes, downloadUrl, forceUpdate);
      }
    } catch (e) {
      debugPrint('Error performing update check: $e');
    }
  }

  bool _isNewerVersion(String currentVersion, String latestVersion, String currentBuild, String? latestBuild) {
    try {
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      final latestParts = latestVersion.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final current = currentParts.length > i ? currentParts[i] : 0;
        final latest = latestParts.length > i ? latestParts[i] : 0;

        if (latest > current) return true;
        if (latest < current) return false;
      }

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
                const Text('What\'s New:', style: TextStyle(fontWeight: FontWeight.bold)),
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