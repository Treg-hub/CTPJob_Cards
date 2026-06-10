import 'package:cloud_firestore/cloud_firestore.dart';

/// Registered machine in the fleet (forklift or grab, or any future asset type).
class FleetAsset {
  final String? id;
  final String typeId;
  final String typeName;
  final String name;
  final String assetTag;
  final String? serial;
  final bool active;
  final double? currentMachineHours;
  final bool hasOpenOosIssue;
  final DateTime? createdAt;

  // Preventive maintenance — both interval types supported (decided
  // 2026-06-10). Intervals are admin-set on the asset form; the last-service
  // baseline is admin-seeded and (in a later phase) auto-stamped when a
  // service-type work record is logged.
  final double? serviceIntervalHours;
  final int? serviceIntervalDays;
  final double? lastServiceMachineHours;
  final DateTime? lastServiceDate;

  const FleetAsset({
    this.id,
    required this.typeId,
    required this.typeName,
    required this.name,
    required this.assetTag,
    this.serial,
    this.active = true,
    this.currentMachineHours,
    this.hasOpenOosIssue = false,
    this.createdAt,
    this.serviceIntervalHours,
    this.serviceIntervalDays,
    this.lastServiceMachineHours,
    this.lastServiceDate,
  });

  /// Hour-based service due: interval set, and the meter has advanced past
  /// the last-service baseline by at least the interval.
  bool get serviceDueByHours {
    final interval = serviceIntervalHours;
    final current = currentMachineHours;
    final last = lastServiceMachineHours;
    if (interval == null || interval <= 0 || current == null || last == null) {
      return false;
    }
    return current - last >= interval;
  }

  /// Calendar-based service due: interval set and enough days have passed
  /// since the last service date.
  bool get serviceDueByDays {
    final interval = serviceIntervalDays;
    final last = lastServiceDate;
    if (interval == null || interval <= 0 || last == null) return false;
    return DateTime.now().difference(last).inDays >= interval;
  }

  bool get serviceDue => active && (serviceDueByHours || serviceDueByDays);

  /// Short human reason, e.g. "1 050 h since service (every 1 000 h)" —
  /// null when not due.
  String? get serviceDueReason {
    if (serviceDueByHours) {
      final since = currentMachineHours! - lastServiceMachineHours!;
      return '${_fmtHours(since)} h since service (every ${_fmtHours(serviceIntervalHours!)} h)';
    }
    if (serviceDueByDays) {
      final days = DateTime.now().difference(lastServiceDate!).inDays;
      return '$days days since service (every $serviceIntervalDays days)';
    }
    return null;
  }

  static String _fmtHours(double h) =>
      h % 1 == 0 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  factory FleetAsset.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetAsset(
      id: doc.id,
      typeId: data['type_id'] as String? ?? '',
      typeName: data['type_name'] as String? ?? '',
      name: data['name'] as String? ?? '',
      assetTag: data['asset_tag'] as String? ?? '',
      serial: data['serial'] as String?,
      active: data['active'] as bool? ?? true,
      currentMachineHours: (data['current_machine_hours'] as num?)?.toDouble(),
      hasOpenOosIssue: data['has_open_oos_issue'] as bool? ?? false,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      serviceIntervalHours:
          (data['service_interval_hours'] as num?)?.toDouble(),
      serviceIntervalDays: (data['service_interval_days'] as num?)?.toInt(),
      lastServiceMachineHours:
          (data['last_service_machine_hours'] as num?)?.toDouble(),
      lastServiceDate: (data['last_service_date'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type_id': typeId,
      'type_name': typeName,
      'name': name,
      'asset_tag': assetTag,
      if (serial != null) 'serial': serial,
      'active': active,
      if (currentMachineHours != null) 'current_machine_hours': currentMachineHours,
      'has_open_oos_issue': hasOpenOosIssue,
      'created_at': FieldValue.serverTimestamp(),
      // PM fields are always written (null clears) so the admin can unset an
      // interval from the form; saveAsset uses merge so other fields keep.
      'service_interval_hours': serviceIntervalHours,
      'service_interval_days': serviceIntervalDays,
      'last_service_machine_hours': lastServiceMachineHours,
      'last_service_date': lastServiceDate != null
          ? Timestamp.fromDate(lastServiceDate!)
          : null,
    };
  }

  FleetAsset copyWith({
    String? id,
    String? typeId,
    String? typeName,
    String? name,
    String? assetTag,
    String? serial,
    bool? active,
    double? currentMachineHours,
    bool? hasOpenOosIssue,
    DateTime? createdAt,
    double? serviceIntervalHours,
    int? serviceIntervalDays,
    double? lastServiceMachineHours,
    DateTime? lastServiceDate,
  }) {
    return FleetAsset(
      id: id ?? this.id,
      typeId: typeId ?? this.typeId,
      typeName: typeName ?? this.typeName,
      name: name ?? this.name,
      assetTag: assetTag ?? this.assetTag,
      serial: serial ?? this.serial,
      active: active ?? this.active,
      currentMachineHours: currentMachineHours ?? this.currentMachineHours,
      hasOpenOosIssue: hasOpenOosIssue ?? this.hasOpenOosIssue,
      createdAt: createdAt ?? this.createdAt,
      serviceIntervalHours: serviceIntervalHours ?? this.serviceIntervalHours,
      serviceIntervalDays: serviceIntervalDays ?? this.serviceIntervalDays,
      lastServiceMachineHours:
          lastServiceMachineHours ?? this.lastServiceMachineHours,
      lastServiceDate: lastServiceDate ?? this.lastServiceDate,
    );
  }
}
