import '../models/ink_count_event.dart';

/// Inclusive lower bound for the open count-to-count period, or null if unbounded
/// (no month-end counts recorded yet).
typedef InkOpenPeriodRange = ({DateTime? fromExclusive, DateTime? toInclusive});

/// Resolves the **current open** period: transactions after the latest count through now.
/// Mirrors `getInkPeriodRange(events, null)` in `web/ctp-pulse/.../inkPeriod.ts`.
InkOpenPeriodRange inkOpenPeriodRange(List<InkCountEvent> events) {
  if (events.isEmpty) {
    return (fromExclusive: null, toInclusive: null);
  }
  final latest = events
      .map((e) => e.countDate)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return (fromExclusive: latest, toInclusive: null);
}

/// True when [date] falls in [range] (open period ends at now when [toInclusive] is null).
bool isWithinInkOpenPeriod(DateTime date, InkOpenPeriodRange range) {
  if (range.fromExclusive != null && !date.isAfter(range.fromExclusive!)) {
    return false;
  }
  if (range.toInclusive != null && date.isAfter(range.toInclusive!)) {
    return false;
  }
  return true;
}