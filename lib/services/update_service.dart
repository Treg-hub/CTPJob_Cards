import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/update_available_screen.dart';
import '../utils/version_compare.dart';

/// Service for checking and handling app updates via Firebase Remote Config,
/// with a Firestore `settings/app` soft-publish fallback (Admin publish form).
///
/// Soft/force prompts open [UpdateAvailableScreen] (in-app APK download +
/// system installer). Hard retirement of broken builds remains the Firestore
/// kill-switch (`settings/app.minSupportedBuild`) — see main.dart.
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

  /// Prevents stacking multiple update routes from resume + cold start.
  bool _showingUpdateUi = false;

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
      'apk_sha256': '',
    });
    _initialized = true;
  }

  /// Silent startup / resume check (respects cooldown). Shows the update
  /// screen only when a newer version is available.
  Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;
    if (_showingUpdateUi) {
      debugPrint('UpdateService: skipped — update UI already visible');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastCheck != null &&
          (now - lastCheck) < _checkInterval.inMilliseconds) {
        final remaining = Duration(
            milliseconds: _checkInterval.inMilliseconds - (now - lastCheck));
        debugPrint(
            'UpdateService: skipped — next check in ${remaining.inMinutes}m');
        return;
      }

      if (!context.mounted) return;
      final result = await _performUpdateCheck(prefs, now);
      debugPrint(
          'UpdateService: ${result.hasUpdate ? "UPDATE AVAILABLE ${result.latestVersion}" : result.configComplete ? "up to date" : "RC keys not configured"}');
      if (result.hasUpdate && context.mounted) {
        await presentUpdate(context, result);
      }
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'update_check_silent', fatal: false);
      }
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

  /// Opens the full-screen update flow (download + install).
  Future<void> presentUpdate(
    BuildContext context,
    UpdateCheckResult result, {
    bool? forceOverride,
  }) async {
    if (!context.mounted || !result.hasUpdate) return;
    if (_showingUpdateUi) return;

    final force = forceOverride ?? result.forceUpdate;
    _showingUpdateUi = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => UpdateAvailableScreen(
            version: result.latestVersion,
            latestBuild: result.latestBuild,
            releaseNotes: result.releaseNotes,
            downloadUrl: result.downloadUrl,
            forceUpdate: force,
            apkSha256: result.apkSha256.isEmpty ? null : result.apkSha256,
          ),
        ),
      );
    } finally {
      _showingUpdateUi = false;
    }
  }

  /// Runs the actual fetch + comparison and returns a structured result.
  /// Never throws — failures are captured in [UpdateCheckResult.error].
  Future<UpdateCheckResult> _performUpdateCheck(
      SharedPreferences prefs, int now) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final currentBuild = packageInfo.buildNumber;
    debugPrint('Current app version: $currentVersion+$currentBuild');

    String latestVersion = '';
    String latestBuild = '';
    String downloadUrl = '';
    bool forceUpdate = false;
    String releaseNotes = '';
    String apkSha256 = '';
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
      apkSha256 = rc.getString('apk_sha256');
      debugPrint(
          'Remote Config -> latest=$latestVersion+$latestBuild url=$downloadUrl force=$forceUpdate');
    } catch (e, st) {
      error = e.toString();
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'remote_config_fetch', fatal: false);
      }
      debugPrint('Remote Config fetch failed: $e');
    }

    // Admin "Publish soft update" writes the same fields to settings/app so
    // floor clients still get prompts if RC is empty or lagging. RC wins when set.
    var fromFirestoreFallback = false;
    try {
      final merged = await _mergePublishedFromFirestore(
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        apkSha256: apkSha256,
        forceUpdate: forceUpdate,
      );
      if (merged.usedFallback) {
        fromFirestoreFallback = true;
        latestVersion = merged.latestVersion;
        latestBuild = merged.latestBuild;
        downloadUrl = merged.downloadUrl;
        releaseNotes = merged.releaseNotes;
        apkSha256 = merged.apkSha256;
        forceUpdate = merged.forceUpdate;
        // Treat Firestore publish as a successful config source when RC failed
        // or was empty — so we don't spin on 1h incomplete retries forever.
        if (!fetchSucceeded &&
            latestVersion.isNotEmpty &&
            downloadUrl.isNotEmpty) {
          fetchSucceeded = true;
          error = null;
        }
        debugPrint(
            'UpdateService: filled gaps from settings/app publish fields');
      }
    } catch (e) {
      debugPrint('UpdateService: settings/app publish merge skipped: $e');
    }

    final configComplete =
        latestVersion.isNotEmpty && downloadUrl.isNotEmpty;
    final hasUpdate = configComplete &&
        isNewerAppVersion(
            currentVersion, latestVersion, currentBuild, latestBuild);

    // Cooldown: full interval when we have a complete config from either source.
    if (configComplete) {
      await prefs.setInt(_lastCheckKey, now);
    } else if (fetchSucceeded || fromFirestoreFallback) {
      final shortRetry = now -
          (_checkInterval.inMilliseconds -
              _incompleteConfigRetry.inMilliseconds);
      await prefs.setInt(_lastCheckKey, shortRetry);
      debugPrint(
          'UpdateService: update keys incomplete — retrying in ${_incompleteConfigRetry.inMinutes}m');
    }

    return UpdateCheckResult(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      downloadUrl: downloadUrl,
      releaseNotes: releaseNotes,
      forceUpdate: forceUpdate,
      apkSha256: apkSha256,
      fetchSucceeded: fetchSucceeded,
      configComplete: configComplete,
      hasUpdate: hasUpdate,
      error: error,
    );
  }

  Future<void> _showDiagnosticDialog(
      BuildContext context, UpdateCheckResult r) async {
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
        : (r.latestBuild.isEmpty
            ? r.latestVersion
            : '${r.latestVersion}+${r.latestBuild}');
    final urlDisplay = r.downloadUrl.isEmpty
        ? '(not set)'
        : (r.downloadUrl.length > 60
            ? '${r.downloadUrl.substring(0, 57)}...'
            : r.downloadUrl);

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        style: TextStyle(
                            color: statusColor, fontWeight: FontWeight.bold),
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
              if (r.apkSha256.isNotEmpty) _kv('SHA-256', 'set'),
              if (r.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Release notes:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(r.releaseNotes),
              ],
              if (r.error != null) ...[
                const SizedBox(height: 8),
                const Text('Error:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
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
                if (context.mounted) {
                  await presentUpdate(context, r);
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
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Fills empty RC fields from Admin-published soft-update metadata on
  /// `settings/app` (same doc as the kill-switch).
  static Future<
      ({
        String latestVersion,
        String latestBuild,
        String downloadUrl,
        String releaseNotes,
        String apkSha256,
        bool forceUpdate,
        bool usedFallback,
      })> _mergePublishedFromFirestore({
    required String latestVersion,
    required String latestBuild,
    required String downloadUrl,
    required String releaseNotes,
    required String apkSha256,
    required bool forceUpdate,
  }) async {
    var v = latestVersion;
    var b = latestBuild;
    var url = downloadUrl;
    var notes = releaseNotes;
    var sha = apkSha256;
    var force = forceUpdate;

    final needsAny = v.isEmpty ||
        url.isEmpty ||
        b.isEmpty ||
        notes.isEmpty ||
        sha.isEmpty ||
        !force;
    if (!needsAny) {
      return (
        latestVersion: v,
        latestBuild: b,
        downloadUrl: url,
        releaseNotes: notes,
        apkSha256: sha,
        forceUpdate: force,
        usedFallback: false,
      );
    }

    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('app')
        .get()
        .timeout(const Duration(seconds: 4));
    final d = doc.data();
    if (d == null) {
      return (
        latestVersion: v,
        latestBuild: b,
        downloadUrl: url,
        releaseNotes: notes,
        apkSha256: sha,
        forceUpdate: force,
        usedFallback: false,
      );
    }

    var used = false;
    String pick(String current, dynamic published) {
      if (current.isNotEmpty) return current;
      final s = published?.toString().trim() ?? '';
      if (s.isNotEmpty) {
        used = true;
        return s;
      }
      return current;
    }

    v = pick(v, d['publishedLatestVersion']);
    b = pick(b, d['publishedLatestBuild']);
    url = pick(url, d['updateDownloadUrl']);
    notes = pick(notes, d['publishedReleaseNotes']);
    sha = pick(sha, d['publishedApkSha256']);
    if (!force && d['publishedForceUpdate'] == true) {
      force = true;
      used = true;
    }

    return (
      latestVersion: v,
      latestBuild: b,
      downloadUrl: url,
      releaseNotes: notes,
      apkSha256: sha,
      forceUpdate: force,
      usedFallback: used,
    );
  }

  /// Browser fallback when in-app install is unavailable.
  Future<void> launchDownloadUrl(BuildContext context, String downloadUrl) async {
    debugPrint('UpdateService: launching download URL: $downloadUrl');
    try {
      final uri = Uri.parse(downloadUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      debugPrint('UpdateService: failed to launch URL – $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'launch_download_url', fatal: false);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Could not open download link. Try visiting the URL manually.\n$downloadUrl')),
        );
      }
    }
  }
}

class UpdateCheckResult {
  final String currentVersion;
  final String currentBuild;
  final String latestVersion;
  final String latestBuild;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final String apkSha256;
  final bool fetchSucceeded;
  final bool configComplete;
  final bool hasUpdate;
  final String? error;

  UpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    this.apkSha256 = '',
    required this.fetchSucceeded,
    required this.configComplete,
    required this.hasUpdate,
    this.error,
  });
}
