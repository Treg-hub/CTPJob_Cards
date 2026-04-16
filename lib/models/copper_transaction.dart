import 'package:cloud_firestore/cloud_firestore.dart';

class CopperTransaction {
  static const String addToSort = 'add_to_sort';
  static const String plateBars = 'plate_bars';
  static const String sort = 'sort';
  static const String useReuse = 'use_reuse';
  static const String recordSale = 'record_sale';

  final String id;
  final String type;
  final double amountKg;
  final String? fromBucket;
  final String? toBucket;
  final Timestamp timestamp;
  final String comments;
  final double? rPerKg;
  final double? totalValueR;
  final String userId;

  const CopperTransaction({
    required this.id,
    required this.type,
    required this.amountKg,
    this.fromBucket,
    this.toBucket,
    required this.timestamp,
    required this.comments,
    this.rPerKg,
    this.totalValueR,
    required this.userId,
  });

  factory CopperTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CopperTransaction(
      id: doc.id,
      type: data['type'] as String? ?? '',
      amountKg: (data['amount_kg'] as num?)?.toDouble() ?? 0.0,
      fromBucket: data['from_bucket'] as String?,
      toBucket: data['to_bucket'] as String?,
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      comments: data['comments'] as String? ?? '',
      rPerKg: (data['r_per_kg'] as num?)?.toDouble(),
      totalValueR: (data['total_value_r'] as num?)?.toDouble(),
      userId: data['user_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'amount_kg': amountKg,
      'from_bucket': fromBucket,
      'to_bucket': toBucket,
      'timestamp': timestamp,
      'comments': comments,
      'r_per_kg': rPerKg,
      'total_value_r': totalValueR,
      'user_id': userId,
    };
  }

  CopperTransaction copyWith({
    String? id,
    String? type,
    double? amountKg,
    String? fromBucket,
    String? toBucket,
    Timestamp? timestamp,
    String? comments,
    double? rPerKg,
    double? totalValueR,
    String? userId,
  }) {
    return CopperTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      amountKg: amountKg ?? this.amountKg,
      fromBucket: fromBucket ?? this.fromBucket,
      toBucket: toBucket ?? this.toBucket,
      timestamp: timestamp ?? this.timestamp,
      comments: comments ?? this.comments,
      rPerKg: rPerKg ?? this.rPerKg,
      totalValueR: totalValueR ?? this.totalValueR,
      userId: userId ?? this.userId,
    );
  }
}
