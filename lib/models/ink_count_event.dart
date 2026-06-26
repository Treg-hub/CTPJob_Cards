import 'package:cloud_firestore/cloud_firestore.dart';

/// One physical inventory count session. Written unconditionally when a
/// month-end count is recorded — even if every item matches the ledger and
/// no adjustment transactions are needed.
class InkCountEvent {
  const InkCountEvent({
    this.id,
    required this.countDate,
    required this.sessionId,
    required this.actorClockNo,
    required this.actorName,
    required this.adjustmentCount,
    required this.lines,
    required this.createdAt,
    this.snapshotVersion = 0,
  });

  final String? id;
  final DateTime countDate;
  final String sessionId;
  final String actorClockNo;
  final String actorName;

  /// Number of items where the physical count differed from the ledger balance.
  final int adjustmentCount;

  /// Full counted quantities for every item entered, including those with zero
  /// variance (ledger matched).
  final List<InkCountLine> lines;

  final DateTime createdAt;

  /// 0 = legacy count with no per-item WAC/value snapshot (the report must fall
  /// back to a genesis replay for opening). >= 1 = the lines carry `wac`/`value`,
  /// so the report can use this count as the opening baseline for the next
  /// period instead of replaying from the beginning of time.
  final int snapshotVersion;

  /// True when this count carries a usable per-item WAC/value snapshot.
  bool get hasSnapshot => snapshotVersion >= 1;

  Map<String, dynamic> toFirestore() => {
        'count_date': Timestamp.fromDate(countDate),
        'session_id': sessionId,
        'actor_clock_no': actorClockNo,
        'actor_name': actorName,
        'adjustment_count': adjustmentCount,
        'snapshot_version': snapshotVersion,
        'lines': [
          for (final l in lines)
            {
              'item_code': l.itemCode,
              'counted': l.counted,
              'ledger_balance': l.ledgerBalance,
              'delta': l.delta,
              'wac': l.wac,
              'value': l.value,
            }
        ],
        'created_at': Timestamp.fromDate(createdAt),
      };

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static InkCountEvent? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return InkCountEvent.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  static InkCountEvent fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkCountEvent(
      id: doc.id,
      countDate: _parseTimestamp(d['count_date']) ?? DateTime.now(),
      sessionId: d['session_id']?.toString() ?? '',
      actorClockNo: d['actor_clock_no']?.toString() ?? '',
      actorName: d['actor_name']?.toString() ?? '',
      adjustmentCount: (d['adjustment_count'] as num?)?.toInt() ?? 0,
      snapshotVersion: (d['snapshot_version'] as num?)?.toInt() ?? 0,
      lines: [
        for (final l in (d['lines'] as List<dynamic>? ?? []))
          if (l is Map<String, dynamic>)
            InkCountLine(
              itemCode: l['item_code']?.toString() ?? '',
              counted: (l['counted'] as num?)?.toDouble() ?? 0,
              ledgerBalance: (l['ledger_balance'] as num?)?.toDouble() ?? 0,
              wac: (l['wac'] as num?)?.toDouble() ?? 0,
              value: (l['value'] as num?)?.toDouble() ?? 0,
            ),
      ],
      createdAt: _parseTimestamp(d['created_at']) ?? DateTime.now(),
    );
  }
}

class InkCountLine {
  const InkCountLine({
    required this.itemCode,
    required this.counted,
    required this.ledgerBalance,
    this.wac = 0,
    this.value = 0,
  });

  final String itemCode;
  final double counted;
  final double ledgerBalance;

  /// WAC at the count date (unchanged by the count adjustment, which moves
  /// quantity at the current WAC). This is the opening WAC baseline the report
  /// replays the next period from. 0 on legacy counts (snapshotVersion 0).
  final double wac;

  /// Snapshot stock value at the count = counted × wac (the "total cost per
  /// item" stored with the count). 0 on legacy counts.
  final double value;

  double get delta => counted - ledgerBalance;
}
