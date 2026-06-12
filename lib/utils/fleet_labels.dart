/// Shared fleet UI copy — fleet machines (forks, grab or BT), not "forklift".
class FleetLabels {
  FleetLabels._();

  static const moduleSubtitle = 'Fleet machines — forks, grab & BT';
  static const hyster = 'Hyster';
  static const whichHyster = 'Which machine?';
  static const whichHysterRequired = 'Which machine? *';
  static const whichHysterForksOrGrab = 'Which machine? (forks, grab or BT)';
  static const whichHysterForksOrGrabRequired =
      'Which machine? (forks, grab or BT) *';
  static const allHyster = 'All machines';
  static const spendPerHyster = 'Spend per machine';
  static const reportHysterProblem = 'Report Machine Problem';
  static const reportProblem = 'Report Problem';
  static const reportIssue = 'Report Issue';

  static String assetLabel({required bool plainUx}) =>
      plainUx ? 'Machine' : 'Asset';

  static String allAssetsLabel({required bool plainUx}) =>
      plainUx ? allHyster : 'All assets';

  static String spendPerAssetLabel({required bool plainUx}) =>
      plainUx ? spendPerHyster : 'Spend per Asset';
}