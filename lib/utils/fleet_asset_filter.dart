import '../models/fleet_asset.dart';

/// Whether [asset] appears in reporter machine pickers for [reporterDepartment].
///
/// - Empty [FleetAsset.departments] → all reporter departments (legacy / shared pool).
/// - Non-empty → reporter's department must be listed (case-insensitive).
/// - Reporter with no department → only unscoped assets (clock-override reporters).
bool fleetAssetVisibleToReporter(
  FleetAsset asset,
  String? reporterDepartment,
) {
  final scopes = asset.departments;
  if (scopes.isEmpty) return true;
  final dept = reporterDepartment?.trim();
  if (dept == null || dept.isEmpty) return false;
  final normalized = dept.toLowerCase();
  return scopes.any((d) => d.trim().toLowerCase() == normalized);
}

List<FleetAsset> filterAssetsForReporter(
  Iterable<FleetAsset> assets,
  String? reporterDepartment,
) {
  return assets
      .where((a) => fleetAssetVisibleToReporter(a, reporterDepartment))
      .toList();
}