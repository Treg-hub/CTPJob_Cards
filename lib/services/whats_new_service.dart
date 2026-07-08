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
/// the changelog before building".
///
/// When the user jumps multiple builds, entries whose headings include
/// `(build N)` with N greater than [lastSeenWhatsNewBuild] are rolled up
/// (capped). Headings without a build number only appear as the single latest
/// entry when no numbered newer sections exist.
///
/// Tracking: `lastSeenWhatsNewBuild` in SharedPreferences.
/// - Fresh installs are stamped during permissions onboarding
///   ([markCurrentBuildSeen]) so brand-new users are not greeted with a changelog.
/// - `null` on an already-onboarded device means "existing user updating into
///   the first build that ships this feature" → show latest once.
class WhatsNewService {
  static final WhatsNewService _instance = WhatsNewService._internal();
  factory WhatsNewService() => _instance;
  WhatsNewService._internal();

  static const String lastSeenBuildKey = 'lastSeenWhatsNewBuild';
  static const String changelogAssetPath = 'docs/CHANGELOG.md';
  static const int maxRollupEntries = 5;

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
      final markdown = extractEntriesSince(
        changelog,
        lastSeen,
        maxEntries: maxRollupEntries,
      );
      if (markdown == null) {
        // Malformed changelog: stamp anyway so we don't retry every launch.
        await prefs.setInt(lastSeenBuildKey, currentBuild);
        return;
      }

      if (!context.mounted) return;
      // Show first, then stamp — so a failed presentation can retry next launch.
      await showWhatsNewSheet(
        context,
        markdown: markdown,
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
    final all = _splitEntries(changelog);
    if (all.isEmpty) return null;
    return all.first.body;
  }

  /// Roll-up of changelog sections newer than [lastSeenBuild].
  ///
  /// - [lastSeenBuild] null → latest entry only (first show of this feature).
  /// - Headings with `(build N)` or `build N` where N > lastSeen are included
  ///   (newest first), capped at [maxEntries].
  /// - If no numbered entries qualify, falls back to the latest entry.
  static String? extractEntriesSince(
    String changelog,
    int? lastSeenBuild, {
    int maxEntries = maxRollupEntries,
  }) {
    final all = _splitEntries(changelog);
    if (all.isEmpty) return null;

    if (lastSeenBuild == null) {
      return all.first.body;
    }

    final newer = <_ChangelogEntry>[];
    for (final e in all) {
      if (e.buildNumber != null && e.buildNumber! > lastSeenBuild) {
        newer.add(e);
      }
    }

    if (newer.isEmpty) {
      // Unnumbered latest release, or user already past all numbered builds
      // but current app build is still higher — show top entry once.
      return all.first.body;
    }

    final capped = newer.take(maxEntries).toList();
    return capped.map((e) => e.body).join('\n\n---\n\n');
  }

  /// Parses `(build 121)` or bare `build 121` from a `## ` heading line.
  static int? parseBuildFromHeading(String headingLine) {
    final paren = RegExp(r'\(build\s+(\d+)\)', caseSensitive: false)
        .firstMatch(headingLine);
    if (paren != null) return int.tryParse(paren.group(1)!);
    final bare =
        RegExp(r'\bbuild\s+(\d+)\b', caseSensitive: false).firstMatch(headingLine);
    if (bare != null) return int.tryParse(bare.group(1)!);
    return null;
  }

  static List<_ChangelogEntry> _splitEntries(String changelog) {
    final lines = changelog.split('\n');
    final starts = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) starts.add(i);
    }
    if (starts.isEmpty) return const [];

    final out = <_ChangelogEntry>[];
    for (var s = 0; s < starts.length; s++) {
      final start = starts[s];
      final end = s + 1 < starts.length ? starts[s + 1] : lines.length;
      final raw = lines.sublist(start, end).join('\n').trim();
      final withoutDivider =
          raw.endsWith('---') ? raw.substring(0, raw.length - 3).trim() : raw;
      if (withoutDivider.isEmpty) continue;
      out.add(_ChangelogEntry(
        heading: lines[start],
        body: withoutDivider,
        buildNumber: parseBuildFromHeading(lines[start]),
      ));
    }
    return out;
  }
}

class _ChangelogEntry {
  final String heading;
  final String body;
  final int? buildNumber;

  const _ChangelogEntry({
    required this.heading,
    required this.body,
    required this.buildNumber,
  });
}
