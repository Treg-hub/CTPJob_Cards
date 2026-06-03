import 'package:cloud_firestore/cloud_firestore.dart';

enum FleetCostCategory {
  parts('parts'),
  labour('labour'),
  invoice('invoice'),
  other('other');

  const FleetCostCategory(this.value);
  final String value;

  static FleetCostCategory fromString(String? value) {
    switch (value) {
      case 'labour':  return FleetCostCategory.labour;
      case 'invoice': return FleetCostCategory.invoice;
      case 'other':   return FleetCostCategory.other;
      default:        return FleetCostCategory.parts;
    }
  }

  String get displayLabel {
    switch (this) {
      case FleetCostCategory.parts:   return 'Parts';
      case FleetCostCategory.labour:  return 'Labour';
      case FleetCostCategory.invoice: return 'Invoice';
      case FleetCostCategory.other:   return 'Other';
    }
  }
}

/// A cost entry associated with a fleet asset (optionally linked to a work record).
/// Only visible to cost managers and admin — never shown to the mechanic.
class FleetCostLine {
  final String? id;
  final String assetId;
  final String assetName;
  final String? workRecordId;
  final String? workNumber;
  final FleetCostCategory category;
  final String description;
  final double amountZar;
  final String? invoiceRef;
  final String? supplier;
  final DateTime costDate;
  final String enteredByClockNo;
  final String enteredByName;
  final DateTime? createdAt;

  const FleetCostLine({
    this.id,
    required this.assetId,
    required this.assetName,
    this.workRecordId,
    this.workNumber,
    required this.category,
    required this.description,
    required this.amountZar,
    this.invoiceRef,
    this.supplier,
    required this.costDate,
    required this.enteredByClockNo,
    required this.enteredByName,
    this.createdAt,
  });

  factory FleetCostLine.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetCostLine(
      id: doc.id,
      assetId: data['asset_id'] as String? ?? '',
      assetName: data['asset_name'] as String? ?? '',
      workRecordId: data['work_record_id'] as String?,
      workNumber: data['work_number'] as String?,
      category: FleetCostCategory.fromString(data['category'] as String?),
      description: data['description'] as String? ?? '',
      amountZar: (data['amount_zar'] as num?)?.toDouble() ?? 0.0,
      invoiceRef: data['invoice_ref'] as String?,
      supplier: data['supplier'] as String?,
      costDate: (data['cost_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      enteredByClockNo: data['entered_by_clock_no'] as String? ?? '',
      enteredByName: data['entered_by_name'] as String? ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'asset_id': assetId,
      'asset_name': assetName,
      if (workRecordId != null) 'work_record_id': workRecordId,
      if (workNumber != null) 'work_number': workNumber,
      'category': category.value,
      'description': description,
      'amount_zar': amountZar,
      if (invoiceRef != null) 'invoice_ref': invoiceRef,
      if (supplier != null) 'supplier': supplier,
      'cost_date': Timestamp.fromDate(costDate),
      'entered_by_clock_no': enteredByClockNo,
      'entered_by_name': enteredByName,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
