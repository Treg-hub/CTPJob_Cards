import '../constants/ink_toloul.dart';
import '../models/ink_tank_level.dart';
import '../models/ink_txn_type.dart';

/// Ledger qty delta to apply to [ink_tank_levels] for this txn, or null if none.
///
/// Quantity signs match the ledger (`consumption_*` negative, additions positive).
double? tankBalanceDeltaForTxn({
  required InkTxnType type,
  required String itemCode,
  required double quantityDelta,
}) {
  if (!isInkTankItem(itemCode)) return null;

  switch (itemCode) {
    case 'yellow':
    case 'red':
    case 'blue':
    case 'black':
      if (type == InkTxnType.consumptionMeter) return quantityDelta;
      return null;
    case 'gravure_binder':
      if (type == InkTxnType.consumptionMeter ||
          type == InkTxnType.manufacture) {
        return quantityDelta;
      }
      return null;
    case kToloulItemCode:
      if (type == InkTxnType.recovery) return quantityDelta;
      // wash, production solvent, and any other consumption_* on toloul
      if (type.isConsumption) return quantityDelta;
      return null;
    default:
      return null;
  }
}
