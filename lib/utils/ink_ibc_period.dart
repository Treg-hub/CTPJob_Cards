import '../models/ink_ibc.dart';
import 'ink_period.dart';

/// True when [ibc] was consumed (transferred) within the open count-to-count period.
bool isIbcConsumedInOpenPeriod(InkIbc ibc, InkOpenPeriodRange range) {
  if (ibc.status != InkIbcStatus.transferred) return false;
  final consumedAt = ibc.transferredDate;
  if (consumedAt == null) return false;
  return isWithinInkOpenPeriod(consumedAt, range);
}

/// Count of IBCs consumed this period per ink colour code.
Map<String, int> ibcConsumedCountByColour(
  List<InkIbc> all,
  InkOpenPeriodRange range,
) {
  final counts = <String, int>{};
  for (final ibc in all) {
    if (!isIbcConsumedInOpenPeriod(ibc, range)) continue;
    counts[ibc.itemCode] = (counts[ibc.itemCode] ?? 0) + 1;
  }
  return counts;
}