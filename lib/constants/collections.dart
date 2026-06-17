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
  // Central geofence/presence audit log (single source of truth). Replaces the
  // legacy split between native `geofence_logs` and Dart `geo_fence_logs`.
  // Written by: native GeofenceReceiver, WorkManager heartbeat, app-open check,
  // web inactivity guard, admin manual toggle, and updateEmployeePresence (CF).
  static const String appGeofence = 'app_geofence';
  static const String alertResponses = 'alertResponses';
  static const String feedback = 'feedback';

  // ----- Fleet Maintenance (fleet_ prefix) -----
  // Hyster machine maintenance (forks or grab attachments) — integrated inside this app.
  // See docs/COLLECTIONS.md for full schema.
  static const String fleetAssets = 'fleet_assets';
  static const String fleetIssues = 'fleet_issues';
  static const String fleetWorkRecords = 'fleet_work_records';
  static const String fleetWorkParts = 'fleet_work_parts'; // sub-collection of fleetWorkRecords
  static const String fleetWorkComments = 'fleet_work_comments'; // sub-collection of fleetWorkRecords
  static const String fleetCostLines = 'fleet_cost_lines';
  static const String fleetTypes = 'fleet_types';
  static const String fleetSettings = 'fleet_settings';
  static const String fleetCounters = 'fleet_counters';
  static const String fleetAudit = 'fleet_audit';

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
  static const String wasteStock = 'waste_stock';

  // ----- Ink Factory (ink_ prefix) -----
  // Full production stock-inventory data-entry system, integrated inside this
  // app as a gated module (department == "Ink Factory"). No data link to Job
  // Cards. Append-only ledger; balances/WAC are derived by replay.
  // See docs/Ink_Factory_Migration_Plan.md for the full schema + domain model.
  static const String inkStockItems = 'ink_stock_items'; // doc id = item code
  static const String inkTransactions = 'ink_transactions'; // append-only ledger
  static const String inkIbcs = 'ink_ibcs'; // IBC audit register
  static const String inkMeterSessions = 'ink_meter_sessions';
  static const String inkProductionRuns = 'ink_production_runs';
  static const String inkRecipes = 'ink_recipes';
  static const String inkConversionFactors = 'ink_conversion_factors';
  static const String inkRecoveries = 'ink_recoveries';
  static const String inkSuppliers = 'ink_suppliers'; // managed list (manager-curated)
  static const String inkCounters = 'ink_counters'; // INK#### sequence
  static const String inkSettings = 'ink_settings';
  static const String inkOtherMeterLogs = 'ink_other_meter_logs'; // report-only, no stock impact
  static const String inkMeterPoints = 'ink_meter_points'; // aux toloul meters (recovery/usage), no stock impact
  static const String inkMeterPointReadings = 'ink_meter_point_readings';
  static const String inkCountEvents = 'ink_count_events'; // one doc per month-end count session
  static const String inkAudit = 'ink_audit';
}
