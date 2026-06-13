import 'package:cloud_firestore/cloud_firestore.dart';

/// Conversion factor for meter readings: `kg = litres × kgPerLitre`.
/// One per meter-read item (the four inks + gravure binder). Manager-managed —
/// meters report litres, the ledger holds kg. The document id is the item code.
class InkConversionFactor {
  const InkConversionFactor({
    required this.itemCode,
    required this.kgPerLitre,
    this.active = true,
    this.updatedAt,
  });

  final String itemCode;
  final double kgPerLitre;
  final bool active;
  final DateTime? updatedAt;

  factory InkConversionFactor.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkConversionFactor(
      itemCode: doc.id,
      kgPerLitre: (d['kg_per_litre'] as num?)?.toDouble() ?? 0,
      active: d['active'] as bool? ?? true,
      updatedAt: (d['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'kg_per_litre': kgPerLitre,
        'active': active,
        'updated_at': FieldValue.serverTimestamp(),
      };
}
