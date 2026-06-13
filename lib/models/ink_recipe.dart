import 'package:cloud_firestore/cloud_firestore.dart';

/// One input line of a recipe: how much of [itemCode] is consumed per pot.
class InkRecipeLine {
  const InkRecipeLine({required this.itemCode, required this.qtyPerPot});
  final String itemCode;
  final double qtyPerPot;

  factory InkRecipeLine.fromMap(Map<String, dynamic> m) => InkRecipeLine(
        itemCode: m['item_code'] as String? ?? '',
        qtyPerPot: (m['qty_per_pot'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() =>
      {'item_code': itemCode, 'qty_per_pot': qtyPerPot};
}

/// A production recipe (`ink_recipes`): consumes [inputs] to produce
/// [outputPerPot] kg of [outputItemCode] per pot. A standard batch is 3 pots
/// (1 or 2 also allowed); quantities scale by the pot count.
class InkRecipe {
  const InkRecipe({
    this.id,
    required this.name,
    required this.outputItemCode,
    required this.outputPerPot,
    this.inputs = const [],
    this.active = true,
    this.version = 1,
  });

  final String? id;
  final String name;
  final String outputItemCode;
  final double outputPerPot;
  final List<InkRecipeLine> inputs;
  final bool active;
  final int version;

  factory InkRecipe.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return InkRecipe(
      id: doc.id,
      name: d['name'] as String? ?? '',
      outputItemCode: d['output_item_code'] as String? ?? '',
      outputPerPot: (d['output_per_pot'] as num?)?.toDouble() ?? 0,
      inputs: (d['inputs'] as List<dynamic>?)
              ?.map((e) => InkRecipeLine.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      active: d['active'] as bool? ?? true,
      version: (d['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'output_item_code': outputItemCode,
        'output_per_pot': outputPerPot,
        'inputs': inputs.map((l) => l.toMap()).toList(),
        'active': active,
        'version': version,
        'updated_at': FieldValue.serverTimestamp(),
      };

  InkRecipe copyWith({
    String? name,
    String? outputItemCode,
    double? outputPerPot,
    List<InkRecipeLine>? inputs,
    bool? active,
    int? version,
  }) =>
      InkRecipe(
        id: id,
        name: name ?? this.name,
        outputItemCode: outputItemCode ?? this.outputItemCode,
        outputPerPot: outputPerPot ?? this.outputPerPot,
        inputs: inputs ?? this.inputs,
        active: active ?? this.active,
        version: version ?? this.version,
      );
}
