/// Pure semver + build comparison for app update checks.
///
/// Returns true when [latestVersion]/[latestBuild] is strictly newer than
/// [currentVersion]+[currentBuild]. Malformed inputs return false.
bool isNewerAppVersion(
  String currentVersion,
  String latestVersion,
  String currentBuild,
  String latestBuild,
) {
  try {
    final currentParts = currentVersion.split('.').map(int.parse).toList();
    final latestParts = latestVersion.split('.').map(int.parse).toList();

    for (var i = 0; i < 3; i++) {
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
  } catch (_) {
    return false;
  }
}
