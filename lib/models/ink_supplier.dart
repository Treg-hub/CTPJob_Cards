import 'package:cloud_firestore/cloud_firestore.dart';

/// A supplier in the managed list (`ink_suppliers`). Managers populate the list
/// and deactivate entries that are no longer used; operators pick from the
/// active ones when receiving stock. Historical transactions keep the supplier
/// NAME (denormalised), so deactivating/renaming a supplier never rewrites past
/// receipts.
class InkSupplier {
  const InkSupplier({
    this.id,
    required this.name,
    this.active = true,
    this.sortOrder = 0,
  });

  final String? id;
  final String name;
  final bool active;
  final int sortOrder;

  factory InkSupplier.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkSupplier(
      id: doc.id,
      name: d['name'] as String? ?? '',
      active: d['active'] as bool? ?? true,
      sortOrder: (d['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'active': active,
        'sort_order': sortOrder,
      };

  InkSupplier copyWith({String? name, bool? active, int? sortOrder}) =>
      InkSupplier(
        id: id,
        name: name ?? this.name,
        active: active ?? this.active,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
