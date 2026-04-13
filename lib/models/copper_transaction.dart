import 'package:cloud_firestore/cloud_firestore.dart';

enum CopperType {
  toSort,
  reuse,
  sellNuggets,
  sellRods,
  soldNuggets,
  soldRods,
}

class CopperTransaction {
  final String id;
  final CopperType type;
  final double kg;
  final String clockNo;
  final DateTime timestamp;
  final String? description;

  const CopperTransaction({
    required this.id,
    required this.type,
    required this.kg,
    required this.clockNo,
    required this.timestamp,
    this.description,
  });

  factory CopperTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CopperTransaction(
      id: doc.id,
      type: CopperType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => CopperType.toSort,
      ),
      kg: (data['kg'] as num?)?.toDouble() ?? 0.0,
      clockNo: data['clockNo'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      description: data['description'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'kg': kg,
      'clockNo': clockNo,
      'timestamp': Timestamp.fromDate(timestamp),
      'description': description,
    };
  }

  CopperTransaction copyWith({
    String? id,
    CopperType? type,
    double? kg,
    String? clockNo,
    DateTime? timestamp,
    String? description,
  }) {
    return CopperTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      kg: kg ?? this.kg,
      clockNo: clockNo ?? this.clockNo,
      timestamp: timestamp ?? this.timestamp,
      description: description ?? this.description,
    );
  }
}