import '../models/ink_purchase_order.dart';
import '../models/ink_shipment.dart';

/// Floor “Expected Orders” horizon: overdue + today through +[kExpectedOrdersHorizonDays] SAST days.
const int kExpectedOrdersHorizonDays = 5;

/// Johannesburg is UTC+2 year-round (no DST) — matches Pulse Ink Today.
const int kSastOffsetHours = 2;

enum InkExpectedKind { localPo, shipment }

enum InkExpectedUrgency {
  overdue,
  today,
  tomorrow,
  inNDays,
}

/// One open local PO or import shipment with an ETA in the floor horizon.
class InkExpectedDelivery {
  const InkExpectedDelivery({
    required this.kind,
    required this.id,
    required this.refLabel,
    required this.headline,
    required this.eta,
    required this.urgency,
    required this.daysUntil,
    this.inDays,
    this.packagingMode,
  });

  final InkExpectedKind kind;
  final String id;

  /// Pulse ref (local) or shipment id (import) — list / multi-row id.
  final String refLabel;

  /// Banner primary detail: local = supplier · products; import = shipment id.
  final String headline;

  final DateTime eta;
  final InkExpectedUrgency urgency;

  /// Calendar days from SAST today to ETA day (negative = overdue).
  final int daysUntil;

  /// Set when [urgency] is [InkExpectedUrgency.inNDays] (2…horizon).
  final int? inDays;

  /// Import only: `ibc` | `pallet` (for receive navigation).
  final String? packagingMode;

  bool get isLocal => kind == InkExpectedKind.localPo;

  bool get isPalletShipment =>
      kind == InkExpectedKind.shipment && packagingMode == 'pallet';
}

/// SAST calendar date (year/month/day only) for [instant].
DateTime sastCalendarDate(DateTime instant) {
  final sast = instant.toUtc().add(const Duration(hours: kSastOffsetHours));
  return DateTime.utc(sast.year, sast.month, sast.day);
}

/// `YYYY-MM-DD` in SAST for [instant].
String sastDayKey(DateTime instant) {
  final d = sastCalendarDate(instant);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Whole SAST calendar days from [from]’s day to [to]’s day.
int sastCalendarDaysBetween(DateTime from, DateTime to) {
  final a = sastCalendarDate(from);
  final b = sastCalendarDate(to);
  return b.difference(a).inDays;
}

/// Days until ETA from [now] (0 = today, negative = overdue).
int daysUntilEta(DateTime eta, {DateTime? now}) {
  return sastCalendarDaysBetween(now ?? DateTime.now(), eta);
}

/// True when ETA is overdue or within [horizonDays] ahead (inclusive).
bool etaInHorizon(
  DateTime eta, {
  DateTime? now,
  int horizonDays = kExpectedOrdersHorizonDays,
}) {
  final d = daysUntilEta(eta, now: now);
  return d <= horizonDays;
}

InkExpectedUrgency urgencyForDaysUntil(int daysUntil) {
  if (daysUntil < 0) return InkExpectedUrgency.overdue;
  if (daysUntil == 0) return InkExpectedUrgency.today;
  if (daysUntil == 1) return InkExpectedUrgency.tomorrow;
  return InkExpectedUrgency.inNDays;
}

/// Short urgency label for chips / banner title.
String expectedUrgencyLabel(InkExpectedUrgency u, {int? inDays}) {
  switch (u) {
    case InkExpectedUrgency.overdue:
      return 'overdue';
    case InkExpectedUrgency.today:
      return 'today';
    case InkExpectedUrgency.tomorrow:
      return 'tomorrow';
    case InkExpectedUrgency.inNDays:
      final n = inDays ?? 0;
      return n == 1 ? 'in 1 day' : 'in $n days';
  }
}

/// Product names for local open lines (fallback: ordered lines).
String localOrderProductSummary(InkPurchaseOrder po) {
  final fromOpen = <String>[];
  for (final e in po.openLines) {
    final name = e.line.displayName.trim();
    if (name.isNotEmpty) fromOpen.add(name);
  }
  final names = fromOpen.isNotEmpty
      ? fromOpen
      : [
          for (final l in po.lines)
            if (l.finalKg > 1e-6 && l.displayName.trim().isNotEmpty)
              l.displayName.trim(),
        ];
  if (names.isEmpty) return 'Open lines';
  if (names.length <= 3) return names.join(', ');
  return '${names.take(3).join(', ')} +${names.length - 3}';
}

String localOrderHeadline(InkPurchaseOrder po) {
  final supplier = po.supplierName.trim().isEmpty
      ? 'Supplier'
      : po.supplierName.trim();
  return '$supplier · ${localOrderProductSummary(po)}';
}

String shipmentProductSummary(InkShipment s) {
  final names = <String>[];
  final seen = <String>{};
  for (final l in s.lines) {
    final code = l.itemCode.trim();
    final desc = (l.description ?? '').trim();
    final label = code.isNotEmpty ? code : desc;
    if (label.isEmpty || seen.contains(label)) continue;
    seen.add(label);
    names.add(label);
  }
  if (names.isEmpty && s.itemCodes.isNotEmpty) {
    names.addAll(s.itemCodes);
  }
  if (names.isEmpty) {
    final n = s.expectedIbcCount;
    return n > 0 ? '$n IBC${n == 1 ? '' : 's'}' : 'Import shipment';
  }
  if (names.length <= 4) return names.join(', ');
  return '${names.take(4).join(', ')} +${names.length - 4}';
}

InkExpectedDelivery? expectedFromLocalPo(
  InkPurchaseOrder po, {
  DateTime? now,
  int horizonDays = kExpectedOrdersHorizonDays,
}) {
  if (!po.isLocalTrack || !po.hasOpenRemaining) return null;
  if (!po.status.isReceiveOpen) return null;
  final eta = po.estimatedArrival;
  if (eta == null) return null;
  if (!etaInHorizon(eta, now: now, horizonDays: horizonDays)) return null;
  final days = daysUntilEta(eta, now: now);
  final urgency = urgencyForDaysUntil(days);
  return InkExpectedDelivery(
    kind: InkExpectedKind.localPo,
    id: po.id,
    refLabel: po.pulseRef,
    headline: localOrderHeadline(po),
    eta: eta,
    urgency: urgency,
    daysUntil: days,
    inDays: urgency == InkExpectedUrgency.inNDays ? days : null,
  );
}

InkExpectedDelivery? expectedFromShipment(
  InkShipment s, {
  DateTime? now,
  int horizonDays = kExpectedOrdersHorizonDays,
}) {
  if (s.status != InkShipmentStatus.awaitingReceipt &&
      s.status != InkShipmentStatus.receiving) {
    return null;
  }
  final eta = s.expectedArrival;
  if (eta == null) return null;
  if (!etaInHorizon(eta, now: now, horizonDays: horizonDays)) return null;
  final days = daysUntilEta(eta, now: now);
  final urgency = urgencyForDaysUntil(days);
  return InkExpectedDelivery(
    kind: InkExpectedKind.shipment,
    id: s.id,
    refLabel: s.id,
    headline: s.id,
    eta: eta,
    urgency: urgency,
    daysUntil: days,
    inDays: urgency == InkExpectedUrgency.inNDays ? days : null,
    packagingMode: s.packagingMode,
  );
}

/// Overdue first, then soonest ETA; stable by ref.
List<InkExpectedDelivery> buildExpectedDeliveries({
  required Iterable<InkPurchaseOrder> localOrders,
  required Iterable<InkShipment> shipments,
  DateTime? now,
  int horizonDays = kExpectedOrdersHorizonDays,
}) {
  final out = <InkExpectedDelivery>[];
  for (final po in localOrders) {
    final row = expectedFromLocalPo(po, now: now, horizonDays: horizonDays);
    if (row != null) out.add(row);
  }
  for (final s in shipments) {
    final row = expectedFromShipment(s, now: now, horizonDays: horizonDays);
    if (row != null) out.add(row);
  }
  out.sort((a, b) {
    final byDays = a.daysUntil.compareTo(b.daysUntil);
    if (byDays != 0) return byDays;
    return a.refLabel.compareTo(b.refLabel);
  });
  return out;
}

/// Sort key for list tiles: overdue/soon first; missing ETA last.
int etaListSortKey(DateTime? eta, {DateTime? now}) {
  if (eta == null) return 1 << 20;
  return daysUntilEta(eta, now: now);
}
