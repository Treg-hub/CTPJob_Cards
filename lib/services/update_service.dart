import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../screens/update_available_screen.dart';
import '../utils/update_channels.dart';
import '../utils/version_compare.dart';

/// App updates via Remote Config + Firestore `settings/app` (channels).
///
/// * **Soft** → [softOffer] for Home banner (no auto full-screen).
/// * **Force** (per matched channel) → full-screen [UpdateAvailableScreen].
/// * **Kill-switch** remains `settings/app.minSupportedBuild` in main.dart.
///
/// Check cadence: 24h when config is complete; 1h retry when incomplete.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _lastCheckKey = 'last_update_check';
  static const String _bannerDismissedBuildKey = 'update_banner_dismissed_build';
  static const String _bannerSnoozeUntilKey = 'update_banner_snooze_until';

  /// Full network check interval when publish config is complete.
  static const Duration checkInterval = Duration(hours: 24);

  /// Short retry when keys are missing/empty.
  static const Duration incompleteConfigRetry = Duration(hours: 1);

  /// Soft-offer snooze after "Later" (banner only).
  static const Duration softSnooze = Duration(hours: 24);

  bool _initialized = false;

  /// Prevents stacking multiple force update routes.
  bool _showingUpdateUi = false;

  /// Soft update for Home banner; null when none / dismissed / force path.
  final ValueNotifier<UpdateCheckResult?> softOffer =
      ValueNotifier<UpdateCheckResult?>(null);

  /// Last successful check (memory) — re-show force on resume without re-fetch.
  UpdateCheckResult? _lastResult;

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

  /// Silent check (respects 24h cooldown). Soft → banner; force → full-screen.
  Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;
    if (_showingUpdateUi) {
      debugPrint('UpdateService: skipped — force UI already visible');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastCheck != null &&
          (now - lastCheck) < checkInterval.inMilliseconds) {
        final remaining = Duration(
            milliseconds: checkInterval.inMilliseconds - (now - lastCheck));
        debugPrint(
            'UpdateService: skipped network — next check in ${remaining.inHours}h ${remaining.inMinutes % 60}m');
        // Force must re-block every resume even inside the 24h window.
        final cached = _lastResult;
        if (cached != null &&
            cached.hasUpdate &&
            cached.forceUpdate &&
            context.mounted) {
          await presentUpdate(context, cached, forceOverride: true);
        }
        return;
      }

      if (!context.mounted) return;
      final result = await _performUpdateCheck(prefs, now);
      _lastResult = result;
      await _applyResult(context, result);
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'update_check_silent', fatal: false);
      }
      debugPrint('UpdateService: error — $e');
    }
  }

  /// Force re-check (no cooldown) — Settings, or after employee profile loads
  /// so cohort matching can run with clock/dept.
  Future<void> checkForUpdateIgnoringCooldown(BuildContext context) async {
    if (kIsWeb) return;
    if (_showingUpdateUi) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.remove(_lastCheckKey);
      if (!context.mounted) return;
      final result = await _performUpdateCheck(prefs, now);
      _lastResult = result;
      await _applyResult(context, result);
    } catch (e, st) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'update_check_immediate', fatal: false);
      }
      debugPrint('UpdateService: immediate check error — $e');
    }
  }

  Future<void> _applyResult(
    BuildContext context,
    UpdateCheckResult result,
  ) async {
    debugPrint(
      'UpdateService: ${result.hasUpdate ? "UPDATE ${result.latestVersion}+${result.latestBuild} "
          "channel=${result.channelId} force=${result.forceUpdate}" : result.configComplete ? "up to date" : "config incomplete"}',
    );

    if (!result.hasUpdate) {
      softOffer.value = null;
      return;
    }

    if (result.forceUpdate) {
      softOffer.value = null;
      if (context.mounted) {
        await presentUpdate(context, result, forceOverride: true);
      }
      return;
    }

    // Soft: banner only (unless snoozed / dismissed for this build).
    final prefs = await SharedPreferences.getInstance();
    if (await _isSoftSuppressed(prefs, result.latestBuild)) {
      softOffer.value = null;
      debugPrint('UpdateService: soft offer suppressed (dismiss/snooze)');
      return;
    }
    softOffer.value = result;
  }

  Future<bool> _isSoftSuppressed(
    SharedPreferences prefs,
    String latestBuild,
  ) async {
    final dismissed = prefs.getString(_bannerDismissedBuildKey) ?? '';
    if (dismissed.isNotEmpty &&
        latestBuild.isNotEmpty &&
        dismissed == latestBuild) {
      return true;
    }
    final snoozeUntil = prefs.getInt(_bannerSnoozeUntilKey) ?? 0;
    if (snoozeUntil > DateTime.now().millisecondsSinceEpoch) {
      return true;
    }
    return false;
  }

  /// "Later" on soft banner — snooze 24h and hide for this session.
  Future<void> dismissSoftOffer({String? forBuild}) async {
    final prefs = await SharedPreferences.getInstance();
    final build = forBuild ?? softOffer.value?.latestBuild ?? '';
    if (build.isNotEmpty) {
      await prefs.setString(_bannerDismissedBuildKey, build);
    }
    await prefs.setInt(
      _bannerSnoozeUntilKey,
      DateTime.now().add(softSnooze).millisecondsSinceEpoch,
    );
    softOffer.value = null;
  }

  /// Manual check from Settings — diagnostic dialog (no cooldown).
  Future<void> forceCheckForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.remove(_lastCheckKey);
    // Clear soft suppress so manual check can show Update Now.
    await prefs.remove(_bannerDismissedBuildKey);
    await prefs.remove(_bannerSnoozeUntilKey);

    debugPrint('Forcing immediate update check...');
    final result = await _performUpdateCheck(prefs, now);
    if (context.mounted) {
      await _showDiagnosticDialog(context, result);
    }
  }

  /// Opens full-screen download + install (soft CTA or force).
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
      await Navigator.of(context, rootNavigator: true).push<void>(
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

  Future<UpdateCheckResult> _performUpdateCheck(
    SharedPreferences prefs,
    int now,
  ) async {
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
    String channelId = 'default';
    bool fetchSucceeded = false;
    String? error;
    Map<String, dynamic>? settingsApp;

    // RC = default-channel seed only (global). Cohorts come from Firestore.
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

    var fromFirestore = false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get()
          .timeout(const Duration(seconds: 6));
      settingsApp = doc.data();
      if (settingsApp != null) {
        fromFirestore = true;
      }
    } catch (e) {
      debugPrint('UpdateService: settings/app read skipped: $e');
    }

    final emp = currentEmployee ?? realEmployee;
    final clockNo = emp?.clockNo;
    final department = emp?.department;

    if (settingsApp != null) {
      final channels = channelsFromSettingsApp(settingsApp);
      final matched = resolveUpdateChannel(
        channels,
        clockNo: clockNo,
        department: department,
      );
      if (matched != null && matched.hasPublishMetadata) {
        channelId = matched.id;
        // Channel metadata wins over RC for the matched cohort (including
        // default when Firestore has a full default channel).
        if (matched.latestVersion.isNotEmpty) {
          latestVersion = matched.latestVersion;
        }
        if (matched.latestBuild.isNotEmpty) latestBuild = matched.latestBuild;
        if (matched.downloadUrl.isNotEmpty) downloadUrl = matched.downloadUrl;
        if (matched.releaseNotes.isNotEmpty) {
          releaseNotes = matched.releaseNotes;
        }
        if (matched.apkSha256.isNotEmpty) apkSha256 = matched.apkSha256;
        // Force is channel-authoritative when channel has version/build set.
        forceUpdate = matched.forceUpdate;
        debugPrint(
            'UpdateService: channel=$channelId force=$forceUpdate build=$latestBuild');
      } else {
        // No channels / empty — merge legacy flat fields into RC gaps.
        final merged = _mergeLegacyFlat(settingsApp, latestVersion, latestBuild,
            downloadUrl, releaseNotes, apkSha256, forceUpdate);
        latestVersion = merged.$1;
        latestBuild = merged.$2;
        downloadUrl = merged.$3;
        releaseNotes = merged.$4;
        apkSha256 = merged.$5;
        forceUpdate = merged.$6;
      }
    }

    // Shared URL fallback.
    if (downloadUrl.isEmpty && settingsApp != null) {
      final shared = (settingsApp['updateDownloadUrl'] ?? '').toString();
      if (shared.isNotEmpty) downloadUrl = shared;
    }

    if (!fetchSucceeded &&
        latestVersion.isNotEmpty &&
        downloadUrl.isNotEmpty) {
      fetchSucceeded = true;
      error = null;
    }

    final configComplete =
        latestVersion.isNotEmpty && downloadUrl.isNotEmpty;
    final hasUpdate = configComplete &&
        isNewerAppVersion(
            currentVersion, latestVersion, currentBuild, latestBuild);

    if (configComplete) {
      await prefs.setInt(_lastCheckKey, now);
    } else if (fetchSucceeded || fromFirestore) {
      final shortRetry = now -
          (checkInterval.inMilliseconds - incompleteConfigRetry.inMilliseconds);
      await prefs.setInt(_lastCheckKey, shortRetry);
      debugPrint(
          'UpdateService: incomplete config — retry in ${incompleteConfigRetry.inHours}h');
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
      channelId: channelId,
      clockNo: clockNo,
      department: department,
      fetchSucceeded: fetchSucceeded,
      configComplete: configComplete,
      hasUpdate: hasUpdate,
      error: error,
    );
  }

  (String, String, String, String, String, bool) _mergeLegacyFlat(
    Map<String, dynamic> d,
    String v,
    String b,
    String url,
    String notes,
    String sha,
    bool force,
  ) {
    String pick(String current, dynamic published) {
      if (current.isNotEmpty) return current;
      return published?.toString().trim() ?? current;
    }

    v = pick(v, d['publishedLatestVersion']);
    b = pick(b, d['publishedLatestBuild']);
    url = pick(url, d['updateDownloadUrl']);
    notes = pick(notes, d['publishedReleaseNotes']);
    sha = pick(sha, d['publishedApkSha256']);
    if (!force && d['publishedForceUpdate'] == true) force = true;
    return (v, b, url, notes, sha, force);
  }

  Future<void> _showDiagnosticDialog(
      BuildContext context, UpdateCheckResult r) async {
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;
    if (!r.fetchSucceeded && r.error != null && !r.configComplete) {
      statusColor = Colors.red;
      statusText = 'Fetch failed';
      statusIcon = Icons.error_outline;
    } else if (!r.configComplete) {
      statusColor = Colors.orange;
      statusText = 'Update keys missing';
      statusIcon = Icons.warning_amber;
    } else if (r.hasUpdate) {
      statusColor = const Color(0xFFFF8C42);
      statusText = r.forceUpdate ? 'Force update required' : 'Update available';
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
              _kv('Channel', r.channelId),
              _kv('Force update', r.forceUpdate ? 'yes' : 'no'),
              if (r.department != null && r.department!.isNotEmpty)
                _kv('Department', r.department!),
              if (r.clockNo != null && r.clockNo!.isNotEmpty)
                _kv('Clock', r.clockNo!),
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
              child: Text(r.forceUpdate ? 'Update required' : 'Update now'),
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

  Future<void> launchDownloadUrl(
      BuildContext context, String downloadUrl) async {
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
  final String channelId;
  final String? clockNo;
  final String? department;
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
    this.channelId = 'default',
    this.clockNo,
    this.department,
    required this.fetchSucceeded,
    required this.configComplete,
    required this.hasUpdate,
    this.error,
  });
}
