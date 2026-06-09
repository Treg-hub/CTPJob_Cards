/// Shared fleet UI copy — Hyster machines (forks or grab), not "forklift".
class FleetLabels {
  FleetLabels._();

  static const moduleSubtitle = 'Hyster machines — forks & grab attachments';
  static const hyster = 'Hyster';
  static const whichHyster = 'Which Hyster?';
  static const whichHysterRequired = 'Which Hyster? *';
  static const whichHysterForksOrGrab = 'Which Hyster? (forks or grab)';
  static const whichHysterForksOrGrabRequired = 'Which Hyster? (forks or grab) *';
  static const allHyster = 'All Hyster';
  static const spendPerHyster = 'Spend per Hyster';
  static const reportHysterProblem = 'Report Hyster Problem';
  static const reportProblem = 'Report Problem';
  static const reportIssue = 'Report Issue';

  static String assetLabel({required bool plainUx}) =>
      plainUx ? hyster : 'Asset';

  static String allAssetsLabel({required bool plainUx}) =>
      plainUx ? allHyster : 'All assets';

  static String spendPerAssetLabel({required bool plainUx}) =>
      plainUx ? spendPerHyster : 'Spend per Asset';
}