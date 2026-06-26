import 'package:cloud_firestore/cloud_firestore.dart';

import 'security_entry.dart';

/// Site gate / boom point from security_gates.
class SecurityGate {
  final String id;
  final String name;
  final String? code;
  final List<SecurityEntryType> allowedEntryTypes;
  final bool active;
  final List<SecurityDirection> directions;
  final int? sortOrder;

  const SecurityGate({
    required this.id,
    required this.name,
    this.code,
    this.allowedEntryTypes = const [],
    this.active = true,
    this.directions = const [
      SecurityDirection.in_,
      SecurityDirection.out,
    ],
    this.sortOrder,
  });

  bool allowsEntryType(SecurityEntryType type) {
    if (allowedEntryTypes.isEmpty) return true;
    return allowedEntryTypes.contains(type);
  }

  bool allowsDirection(SecurityDirection direction) {
    if (directions.isEmpty) return true;
    return directions.contains(direction);
  }

  factory SecurityGate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SecurityGate(
      id: doc.id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String?,
      allowedEntryTypes: _parseEntryTypes(data['allowed_entry_types']),
      active: data['active'] as bool? ?? true,
      directions: _parseDirections(data['directions']),
      sortOrder: (data['sort_order'] as num?)?.toInt(),
    );
  }

  static List<SecurityEntryType> _parseEntryTypes(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => SecurityEntryType.fromString(e?.toString()))
        .whereType<SecurityEntryType>()
        .toList();
  }

  static List<SecurityDirection> _parseDirections(dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return const [SecurityDirection.in_, SecurityDirection.out];
    }
    return raw
        .map((e) => SecurityDirection.fromString(e?.toString()))
        .whereType<SecurityDirection>()
        .toList();
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        if (code != null) 'code': code,
        'allowed_entry_types':
            allowedEntryTypes.map((t) => t.value).toList(),
        'active': active,
        'directions': directions.map((d) => d.value).toList(),
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}