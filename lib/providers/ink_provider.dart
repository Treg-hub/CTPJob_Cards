import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_conversion_factor.dart';
import '../models/ink_recipe.dart';
import '../models/ink_settings.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_supplier.dart';
import '../models/ink_transaction.dart';
import '../services/ink_service.dart';

final inkServiceProvider = Provider<InkService>((ref) => InkService());

/// Module settings (ink_enabled + closed periods). Loaded once per session and
/// used for home-screen gating, mirroring fleetSettingsProvider.
final inkSettingsProvider = StreamProvider<InkSettings>(
  (ref) => ref.watch(inkServiceProvider).watchSettings(),
);

/// All active stock items with their cached balance/WAC.
final inkStockItemsProvider = StreamProvider<List<InkStockItem>>(
  (ref) => ref.watch(inkServiceProvider).watchStockItems(),
);

/// One stock item's ledger, oldest-effective first.
final inkItemLedgerProvider =
    StreamProvider.family<List<InkTransaction>, String>(
  (ref, itemCode) => ref.watch(inkServiceProvider).watchItemLedger(itemCode),
);

/// Manager "pending costs" queue.
final inkPendingCostsProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchPendingCosts(),
);

/// Manager review queue (flagged movements).
final inkFlaggedProvider = StreamProvider<List<InkTransaction>>(
  (ref) => ref.watch(inkServiceProvider).watchFlagged(),
);

/// Active suppliers (for the receive picker).
final inkActiveSuppliersProvider = StreamProvider<List<InkSupplier>>(
  (ref) => ref.watch(inkServiceProvider).watchSuppliers(activeOnly: true),
);

/// All suppliers incl. inactive (for the manager management screen).
final inkAllSuppliersProvider = StreamProvider<List<InkSupplier>>(
  (ref) => ref.watch(inkServiceProvider).watchSuppliers(activeOnly: false),
);

/// Conversion factors (litres→kg) keyed by item code.
final inkConversionFactorsProvider =
    StreamProvider<Map<String, InkConversionFactor>>(
  (ref) => ref.watch(inkServiceProvider).watchConversionFactors(),
);

/// Latest cumulative meter reading per item code.
final inkLatestMeterReadingsProvider = StreamProvider<Map<String, double>>(
  (ref) => ref.watch(inkServiceProvider).watchLatestMeterReadings(),
);

/// Active recipes (for the production picker).
final inkRecipesProvider = StreamProvider<List<InkRecipe>>(
  (ref) => ref.watch(inkServiceProvider).watchRecipes(activeOnly: true),
);

/// All recipes incl. inactive (for the manager management screen).
final inkAllRecipesProvider = StreamProvider<List<InkRecipe>>(
  (ref) => ref.watch(inkServiceProvider).watchRecipes(activeOnly: false),
);
