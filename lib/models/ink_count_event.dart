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

  Map<String, dynamic> toFirestore() => {
        'count_date': Timestamp.fromDate(countDate),
        'session_id': sessionId,
        'actor_clock_no': actorClockNo,
        'actor_name': actorName,
        'adjustment_count': adjustmentCount,
        'lines': [
          for (final l in lines)
            {
              'item_code': l.itemCode,
              'counted': l.counted,
              'ledger_balance': l.ledgerBalance,
              'delta': l.delta,
            }
        ],
        'created_at': Timestamp.fromDate(createdAt),
      };

  static InkCountEvent fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return InkCountEvent(
      id: doc.id,
      countDate: (d['count_date'] as Timestamp).toDate(),
      sessionId: d['session_id'] as String? ?? '',
      actorClockNo: d['actor_clock_no'] as String? ?? '',
      actorName: d['actor_name'] as String? ?? '',
      adjustmentCount: d['adjustment_count'] as int? ?? 0,
      lines: [
        for (final l in (d['lines'] as List<dynamic>? ?? []))
          InkCountLine(
            itemCode: (l as Map<String, dynamic>)['item_code'] as String,
            counted: (l['counted'] as num).toDouble(),
            ledgerBalance: (l['ledger_balance'] as num).toDouble(),
          )
      ],
      createdAt: (d['created_at'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }
}

class InkCountLine {
  const InkCountLine({
    required this.itemCode,
    required this.counted,
    required this.ledgerBalance,
  });

  final String itemCode;
  final double counted;
  final double ledgerBalance;
  double get delta => counted - ledgerBalance;
}
