import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for checking and handling app updates via Firebase Remote Config.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _lastCheckKey = 'last_update_check';
  // Full check interval when Remote Config is properly configured.
  static const Duration _checkInterval = Duration(hours: 4);
  // Short retry when RC keys are missing/empty — so a misconfiguration
  // doesn't silence update checks for a full day.
  static const Duration _incompleteConfigRetry = Duration(hours: 1);

  bool _initialized = false;

  /// Configure Remote Config on first use. We force a zero SDK-side
  /// minimumFetchInterval so every fetchAndActivate() actually hits the
  /// network — cadence is enforced by our own SharedPreferences cooldown.
  Future<void> _ensureRemoteConfigReady() async {
    if (_initialized) return;
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: Duration.zero,
    ));
    await rc.setDefaults(const {
      'latest_version': '',
      'latest_build': '',
      'download_url': '',
      'force_update': false,
      'release_notes': '',
    });
    _initialized = true;
  }

  /// Silent startup check (respects cooldown). Shows the standard update
  /// dialog only when a newer version is available.
  /// - Full 4-hour cooldown when RC is properly configured.
  /// - 1-hour retry when RC keys are missing, so a setup mistake doesn't
  ///   silence checks for a full day.
  Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastCheck != null && (now - lastCheck) < _checkInterval.inMilliseconds) {
        final remaining = Duration(milliseconds: _checkInterval.inMilliseconds - (now - lastCheck));
        debugPrint('UpdateService: skipped — next check in ${remaining.inMinutes}m');
        return;
      }

      if (!context.mounted) return;
      final result = await _performUpdateCheck(prefs, now);
      debugPrint('UpdateService: ${result.hasUpdate ? "UPDATE AVAILABLE ${result.latestVersion}" : result.configComplete ? "up to date" : "RC keys not configured"}');
      if (result.hasUpdate && context.mounted) {
        await _showUpdateDialog(
          context,
          result.latestVersion,
          result.releaseNotes,
          result.downloadUrl,
          result.forceUpdate,
        );
      }
    } catch (e, st) {
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st, reason: 'update_check_silent', fatal: false);
      debugPrint('UpdateService: error — $e');
    }
  }

  /// Manual check from Settings → "Check for Update". Ignores cooldown and
  /// always surfaces a diagnostic dialog so the user can see exactly what
  /// Remote Config returned (or why the check failed).
  Future<void> forceCheckForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.remove(_lastCheckKey);

    debugPrint('Forcing immediate update check...');
    final result = await _performUpdateCheck(prefs, now);
    if (context.mounted) {
      await _showDiagnosticDialog(context, result);
    }
  }

  /// Runs the actual fetch + comparison and returns a structured result.
  /// Never throws — failures are captured in [_UpdateCheckResult.error] so
  /// the diagnostic dialog can render them.
  Future<_UpdateCheckResult> _performUpdateCheck(SharedPreferences prefs, int now) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final currentBuild = packageInfo.buildNumber;
    debugPrint('Current app version: $currentVersion+$currentBuild');

    String latestVersion = '';
    String latestBuild = '';
    String downloadUrl = '';
    bool forceUpdate = false;
    String releaseNotes = '';
    bool fetchSucceeded = false;
    String? error;

    try {
      await _ensureRemoteConfigReady();
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      fetchSucceeded = true;

      final rc = FirebaseRemoteConfig.instance;
      latestVersion = rc.getString('latest_version');
      latestBuild = rc.getString('latest_build');
      downloadUrl = rc.getString('download_url');
      forceUpdate = rc.getBool('force_update');
      releaseNotes = rc.getString('release_notes');
      debugPrint('Remote Config -> latest=$latestVersion+$latestBuild url=$downloadUrl force=$forceUpdate');
    } catch (e, st) {
      error = e.toString();
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st, reason: 'remote_config_fetch', fatal: false);
      debugPrint('Remote Config fetch failed: $e');
    }

    final configComplete = fetchSucceeded && latestVersion.isNotEmpty && downloadUrl.isNotEmpty;
    final hasUpdate = configComplete &&
        _isNewerVersion(currentVersion, latestVersion, currentBuild, latestBuild);

    if (fetchSucceeded) {
      if (configComplete) {
        // Full cooldown — config is set up correctly.
        await prefs.setInt(_lastCheckKey, now);
      } else {
        // RC fetched OK but keys are empty. Use a short retry so a
        // misconfiguration doesn't silence update prompts for 4 hours.
        final shortRetry = now - (_checkInterval.inMilliseconds - _incompleteConfigRetry.inMilliseconds);
        await prefs.setInt(_lastCheckKey, shortRetry);
        debugPrint('UpdateService: RC keys incomplete — retrying in ${_incompleteConfigRetry.inMinutes}m');
      }
    }

    return _UpdateCheckResult(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      downloadUrl: downloadUrl,
      releaseNotes: releaseNotes,
      forceUpdate: forceUpdate,
      fetchSucceeded: fetchSucceeded,
      configComplete: configComplete,
      hasUpdate: hasUpdate,
      error: error,
    );
  }

  bool _isNewerVersion(String currentVersion, String latestVersion, String currentBuild, String latestBuild) {
    try {
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      final latestParts = latestVersion.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final current = currentParts.length > i ? currentParts[i] : 0;
        final latest = latestParts.length > i ? latestParts[i] : 0;

        if (latest > current) return true;
        if (latest < current) return false;
      }

      if (latestBuild.isNotEmpty) {
        final currentBuildNum = int.tryParse(currentBuild) ?? 0;
        final latestBuildNum = int.tryParse(latestBuild) ?? 0;
        return latestBuildNum > currentBuildNum;
      }

      return false;
    } catch (e, st) {
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st, reason: 'version_compare', fatal: false);
      debugPrint('Error comparing versions: $e');
      return false;
    }
  }

  Future<void> _showDiagnosticDialog(BuildContext context, _UpdateCheckResult r) async {
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;
    if (!r.fetchSucceeded) {
      statusColor = Colors.red;
      statusText = 'Fetch failed';
      statusIcon = Icons.error_outline;
    } else if (!r.configComplete) {
      statusColor = Colors.orange;
      statusText = 'Remote Config keys missing';
      statusIcon = Icons.warning_amber;
    } else if (r.hasUpdate) {
      statusColor = const Color(0xFFFF8C42);
      statusText = 'Update available';
      statusIcon = Icons.system_update;
    } else {
      statusColor = Colors.green;
      statusText = 'Up to date';
      statusIcon = Icons.check_circle;
    }

    final latestDisplay = r.latestVersion.isEmpty
        ? '(not set)'
        : (r.latestBuild.isEmpty ? r.latestVersion : '${r.latestVersion}+${r.latestBuild}');
    final urlDisplay = r.downloadUrl.isEmpty
        ? '(not set)'
        : (r.downloadUrl.length > 60 ? '${r.downloadUrl.substring(0, 57)}...' : r.downloadUrl);

    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Update check'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _kv('Current', '${r.currentVersion}+${r.currentBuild}'),
              _kv('Latest', latestDisplay),
              _kv('Force update', r.forceUpdate ? 'yes' : 'no'),
              _kv('Download URL', urlDisplay),
              if (r.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Release notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(r.releaseNotes),
              ],
              if (r.error != null) ...[
                const SizedBox(height: 8),
                const Text('Error:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 4),
                Text(r.error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          if (r.hasUpdate && r.downloadUrl.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await _launchDownload(context, r.downloadUrl);
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

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _launchDownload(BuildContext context, String downloadUrl) async {
    debugPrint('UpdateService: launching download URL: $downloadUrl');
    try {
      final uri = Uri.parse(downloadUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      debugPrint('UpdateService: failed to launch URL – $e');
      if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st, reason: 'launch_download_url', fatal: false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open download link. Try visiting the URL manually.\n$downloadUrl')),
        );
      }
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
      builder: (context) => PopScope(
        canPop: !forceUpdate,
        child: AlertDialog(
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
              onPressed: () {
                Navigator.of(context).pop();
                _launchDownload(context, downloadUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C42),
                foregroundColor: Colors.black,
              ),
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateCheckResult {
  final String currentVersion;
  final String currentBuild;
  final String latestVersion;
  final String latestBuild;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final bool fetchSucceeded;
  final bool configComplete;
  final bool hasUpdate;
  final String? error;

  _UpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.fetchSucceeded,
    required this.configComplete,
    required this.hasUpdate,
    this.error,
  });
}
