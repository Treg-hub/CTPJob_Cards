/// Canonical Firestore collection names for the CTP Job Cards app.
///
/// This is the Dart half of a cross-language contract. The same names are
/// mirrored in:
///   - docs/COLLECTIONS.md                     (registry + rationale)
///   - packages/shared-ts/src/collections.ts   (TypeScript mirror, web apps)
/// Change a name in ALL THREE places together.
///
/// Job Cards collections are UNPREFIXED (this is the live, legacy-owner app).
/// `employees` is shared across every app. See docs/COLLECTIONS.md.
class Collections {
  Collections._();

  // ----- Shared -----
  static const String employees = 'employees';

  // ----- Job Cards (no prefix) -----
  static const String jobCards = 'job_cards';
  static const String jobCardAudit = 'job_card_audit';
  static const String counters = 'counters';
  static const String structures = 'structures';
  static const String settings = 'settings';
  static const String notificationConfigs = 'notification_configs';
  static const String notifications = 'notifications';
  static const String copperTransactions = 'copper_transactions';
  static const String copperInventory = 'copper_inventory';
  static const String geoFenceLogs = 'geo_fence_logs';
  static const String alertResponses = 'alertResponses';
  static const String feedback = 'feedback';

  // ----- Waste Management / WasteTrack (waste_ prefix) -----
  // Integrated inside this app. See docs/COLLECTIONS.md for full rationale.
  static const String wasteLoads = 'waste_loads';
  static const String wasteItems = 'waste_items';
  static const String wasteTypes = 'waste_types';
  static const String wasteContractors = 'waste_contractors';
  static const String wasteCollectionCompanies = 'waste_collection_companies';
  static const String wasteRates = 'waste_rates';
  static const String wasteDeletedLoads = 'waste_deleted_loads';
  static const String wasteSettings = 'waste_settings';
  static const String wasteAudit = 'waste_audit';
  static const String wasteUsageLogs = 'waste_usage_logs';
  static const String wasteCounters = 'waste_counters';
}
