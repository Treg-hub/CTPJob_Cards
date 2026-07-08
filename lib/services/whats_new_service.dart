import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/whats_new_sheet.dart';

/// Shows a one-time "What's changed" sheet the first time a user opens a
/// build newer than the one they last used.
///
/// Source of truth is the bundled `docs/CHANGELOG.md` (the same file behind
/// Settings → Documentation → Changelog), so release notes ship inside the
/// APK itself — no network needed, and the release discipline stays "update
/// the changelog before building" (the sheet shows whatever the top entry is).
///
/// Tracking: `lastSeenWhatsNewBuild` in SharedPreferences.
/// - Fresh installs are stamped during permissions onboarding
///   ([markCurrentBuildSeen]) so brand-new users — who just read the full
///   onboarding — are not greeted with a changelog too.
/// - `null` on an already-onboarded device therefore means "existing user
///   updating into the first build that ships this feature" → show once.
class WhatsNewService {
  static final WhatsNewService _instance = WhatsNewService._internal();
  factory WhatsNewService() => _instance;
  WhatsNewService._internal();

  static const String lastSeenBuildKey = 'lastSeenWhatsNewBuild';
  static const String changelogAssetPath = 'docs/CHANGELOG.md';

  /// Stamps the current build as seen without showing anything. Called when
  /// permissions onboarding completes so first-time users skip the sheet.
  Future<void> markCurrentBuildSeen() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      if (build <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(lastSeenBuildKey, build);
    } catch (e) {
      debugPrint('WhatsNewService: markCurrentBuildSeen failed: $e');
    }
  }

  /// Shows the sheet when this build is newer than the last one seen.
  /// Never throws; any failure is skipped silently so it can't block Home.
  Future<void> maybeShowWhatsNew(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (currentBuild <= 0) return;

      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(lastSeenBuildKey);
      // Same build, or a downgrade/sideload of an older APK — nothing to show.
      if (lastSeen != null && lastSeen >= currentBuild) return;

      // A notification deep link may have pushed a detail screen on top of
      // Home. Don't stamp or show — the sheet will appear on the next launch.
      if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }

      final changelog = await rootBundle.loadString(changelogAssetPath);
      final latest = extractLatestEntry(changelog);
      if (latest == null) {
        // Malformed changelog: stamp anyway so we don't retry every launch.
        await prefs.setInt(lastSeenBuildKey, currentBuild);
        return;
      }

      if (!context.mounted) return;
      // Show first, then stamp — so a failed presentation can retry next launch.
      await showWhatsNewSheet(
        context,
        markdown: latest,
        versionLabel: 'v${info.version} (build ${info.buildNumber})',
      );
      // Stamp after the sheet closes (Got it, swipe, or full-changelog nav pop
      // of the sheet itself). Once per build regardless of how it was dismissed.
      final prefsAfter = await SharedPreferences.getInstance();
      await prefsAfter.setInt(lastSeenBuildKey, currentBuild);
    } catch (e) {
      debugPrint('WhatsNewService: skipped ($e)');
    }
  }

  /// Returns the newest changelog entry: the first `## ` section, without its
  /// trailing `---` divider. Null when no `## ` heading exists.
  ///
  /// Pure and static so it is unit-testable without Flutter bindings.
  static String? extractLatestEntry(String changelog) {
    final lines = changelog.split('\n');
    int? start;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) {
        start = i;
        break;
      }
    }
    if (start == null) return null;

    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) {
        end = i;
        break;
      }
    }

    final entry = lines.sublist(start, end).join('\n').trim();
    final withoutDivider =
        entry.endsWith('---') ? entry.substring(0, entry.length - 3) : entry;
    final result = withoutDivider.trim();
    return result.isEmpty ? null : result;
  }
}
