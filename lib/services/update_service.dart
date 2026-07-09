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

/// App updates via Firestore `settings/app` (Admin App Update Control) first,
/// with Remote Config only as a **last-resort seed** for empty fields.
///
/// * **Soft** → [softOffer] for Home banner (no auto full-screen).
/// * **Force** (per matched channel) → full-screen [UpdateAvailableScreen].
/// * **Kill-switch** remains `settings/app.minSupportedBuild` in main.dart.
///
/// Priority (highest first): matched `updateChannels` → shared
/// `updateDownloadUrl` / legacy publish fields → Remote Config gaps only.
/// This prevents a stale RC App Distribution URL from winning over Admin Hosting.
///
/// Check cadence:
/// * **Cold start / resume / employee cohort ready** → network re-check
///   ([checkForUpdateIgnoringCooldown]) so newly published force applies
///   without waiting 24h on long-lived sessions.
/// * **Other silent paths** may still use [checkForUpdate] (24h when complete;
///   1h retry when incomplete).
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _lastCheckKey = 'last_update_check';
  /// Legacy key: older builds permanently hid soft offers per build. Cleared on
  /// Later / Settings check; no longer written for suppress.
  static const String _bannerDismissedBuildKey = 'update_banner_dismissed_build';
  static const String _bannerSnoozeUntilKey = 'update_banner_snooze_until';

  /// Full network check interval when publish config is complete (silent path).
  static const Duration checkInterval = Duration(hours: 24);

  /// Short retry when keys are missing/empty.
  static const Duration incompleteConfigRetry = Duration(hours: 1);

  /// Soft-offer snooze after "Later" (banner only) — not permanent per build.
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
  /// Prefer [checkForUpdateOnResume] / [checkForUpdateIgnoringCooldown] when a
  /// newly published force must apply without waiting for the cooldown.
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
        // In-memory force only (same process). Resume uses network re-check.
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

  /// Network re-check with no cooldown — Home cold start (cohort), app resume
  /// (newly published force), and deferred employee load for channel match.
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

  /// App resume: always re-fetch so Admin force published while the app was
  /// backgrounded (or after an "up to date" check) still blocks this session.
  Future<void> checkForUpdateOnResume(BuildContext context) =>
      checkForUpdateIgnoringCooldown(context);

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

    // Soft: banner only (unless snoozed ~24h).
    final prefs = await SharedPreferences.getInstance();
    if (await _isSoftSuppressed(prefs)) {
      softOffer.value = null;
      debugPrint('UpdateService: soft offer suppressed (snooze)');
      return;
    }
    softOffer.value = result;
  }

  Future<bool> _isSoftSuppressed(SharedPreferences prefs) async {
    final snoozeUntil = prefs.getInt(_bannerSnoozeUntilKey) ?? 0;
    if (snoozeUntil > DateTime.now().millisecondsSinceEpoch) {
      return true;
    }
    return false;
  }

  /// "Later" on soft banner — snooze ~24h only (not permanent for that build).
  /// Clears any legacy per-build dismiss flag from older app versions.
  Future<void> dismissSoftOffer() async {
    final prefs = await SharedPreferences.getInstance();
    // Drop legacy permanent-dismiss so older installs recover after this update.
    await prefs.remove(_bannerDismissedBuildKey);
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

    // Start empty — Firestore Admin publish is source of truth; RC fills gaps only.
    String latestVersion = '';
    String latestBuild = '';
    String downloadUrl = '';
    bool forceUpdate = false;
    String releaseNotes = '';
    String apkSha256 = '';
    String channelId = 'default';
    String configSource = 'none';
    bool fetchSucceeded = false;
    String? error;
    Map<String, dynamic>? settingsApp;

    // ── 1) Firestore settings/app (Admin App Update Control) ───────────────
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
        if (matched.latestVersion.isNotEmpty) {
          latestVersion = matched.latestVersion;
        }
        if (matched.latestBuild.isNotEmpty) latestBuild = matched.latestBuild;
        if (matched.downloadUrl.isNotEmpty) downloadUrl = matched.downloadUrl;
        if (matched.releaseNotes.isNotEmpty) {
          releaseNotes = matched.releaseNotes;
        }
        if (matched.apkSha256.isNotEmpty) apkSha256 = matched.apkSha256;
        forceUpdate = matched.forceUpdate;
        configSource = 'firestore:$channelId';
        debugPrint(
            'UpdateService: channel=$channelId force=$forceUpdate build=$latestBuild');
      } else {
        // Legacy flat fields on settings/app (no channel metadata yet).
        latestVersion = (settingsApp['publishedLatestVersion'] ?? '')
            .toString()
            .trim();
        latestBuild =
            (settingsApp['publishedLatestBuild'] ?? '').toString().trim();
        downloadUrl =
            (settingsApp['updateDownloadUrl'] ?? '').toString().trim();
        releaseNotes =
            (settingsApp['publishedReleaseNotes'] ?? '').toString().trim();
        apkSha256 =
            (settingsApp['publishedApkSha256'] ?? '').toString().trim();
        forceUpdate = settingsApp['publishedForceUpdate'] == true;
        if (latestVersion.isNotEmpty ||
            latestBuild.isNotEmpty ||
            downloadUrl.isNotEmpty) {
          configSource = 'firestore:legacy';
        }
      }

      // Shared download URL fills channel gaps (Admin field).
      if (downloadUrl.isEmpty) {
        final shared =
            (settingsApp['updateDownloadUrl'] ?? '').toString().trim();
        if (shared.isNotEmpty) downloadUrl = shared;
      }
    }

    // ── 2) Remote Config — only empty fields (never override Admin URL) ────
    try {
      await _ensureRemoteConfigReady();
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      fetchSucceeded = true;

      final rc = FirebaseRemoteConfig.instance;
      final rcVersion = rc.getString('latest_version').trim();
      final rcBuild = rc.getString('latest_build').trim();
      final rcUrl = rc.getString('download_url').trim();
      final rcNotes = rc.getString('release_notes').trim();
      final rcSha = rc.getString('apk_sha256').trim();
      final rcForce = rc.getBool('force_update');

      debugPrint(
          'Remote Config (gap-fill only) -> latest=$rcVersion+$rcBuild url=$rcUrl force=$rcForce');

      if (latestVersion.isEmpty && rcVersion.isNotEmpty) {
        latestVersion = rcVersion;
        if (configSource == 'none') configSource = 'remote_config';
      }
      if (latestBuild.isEmpty && rcBuild.isNotEmpty) {
        latestBuild = rcBuild;
        if (configSource == 'none') configSource = 'remote_config';
      }
      if (downloadUrl.isEmpty && rcUrl.isNotEmpty) {
        downloadUrl = rcUrl;
        if (configSource == 'none') configSource = 'remote_config';
      }
      if (releaseNotes.isEmpty && rcNotes.isNotEmpty) {
        releaseNotes = rcNotes;
      }
      if (apkSha256.isEmpty && rcSha.isNotEmpty) {
        apkSha256 = rcSha;
      }
      // Force: only seed from RC when Firestore did not supply channel/legacy force.
      if (!fromFirestore && rcForce) {
        forceUpdate = true;
      }
    } catch (e, st) {
      error = e.toString();
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'remote_config_fetch', fatal: false);
      }
      debugPrint('Remote Config fetch failed: $e');
    }

    if (!fetchSucceeded &&
        latestVersion.isNotEmpty &&
        downloadUrl.isNotEmpty) {
      fetchSucceeded = true;
      error = null;
    }

    debugPrint(
        'UpdateService: source=$configSource latest=$latestVersion+$latestBuild url=$downloadUrl force=$forceUpdate');

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
      configSource: configSource,
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
              _kv('Config source', r.configSource),
              _kv('Force update', r.forceUpdate ? 'yes' : 'no'),
              if (r.department != null && r.department!.isNotEmpty)
                _kv('Department', r.department!),
              if (r.clockNo != null && r.clockNo!.isNotEmpty)
                _kv('Clock', r.clockNo!),
              _kv('Download URL', urlDisplay),
              if (r.downloadUrl.contains('appdistribution.firebase'))
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'This URL is Firebase App Distribution (login page) — set Admin Shared download URL to the Hosting latest.apk link.',
                    style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.3),
                  ),
                ),
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
  /// e.g. `firestore:default`, `firestore:legacy`, `remote_config`, `none`.
  final String configSource;
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
    this.configSource = 'none',
    required this.fetchSucceeded,
    required this.configComplete,
    required this.hasUpdate,
    this.error,
  });
}
