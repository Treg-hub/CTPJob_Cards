import 'package:cloud_firestore/cloud_firestore.dart';

enum FleetIssueSeverity {
  low('low'),
  medium('medium'),
  high('high'),
  outOfService('out_of_service');

  const FleetIssueSeverity(this.value);
  final String value;

  static FleetIssueSeverity fromString(String? value) {
    switch (value) {
      case 'medium':       return FleetIssueSeverity.medium;
      case 'high':         return FleetIssueSeverity.high;
      case 'out_of_service': return FleetIssueSeverity.outOfService;
      default:             return FleetIssueSeverity.low;
    }
  }

  String get displayLabel {
    switch (this) {
      case FleetIssueSeverity.low:          return 'Low';
      case FleetIssueSeverity.medium:       return 'Medium';
      case FleetIssueSeverity.high:         return 'High';
      case FleetIssueSeverity.outOfService: return 'Out of Service';
    }
  }

  int get sortOrder {
    switch (this) {
      case FleetIssueSeverity.outOfService: return 0;
      case FleetIssueSeverity.high:         return 1;
      case FleetIssueSeverity.medium:       return 2;
      case FleetIssueSeverity.low:          return 3;
    }
  }
}

enum FleetIssueStatus {
  open('open'),
  acknowledged('acknowledged'),
  resolved('resolved'),
  cancelled('cancelled');

  const FleetIssueStatus(this.value);
  final String value;

  static FleetIssueStatus fromString(String? value) {
    switch (value) {
      case 'acknowledged': return FleetIssueStatus.acknowledged;
      case 'resolved':     return FleetIssueStatus.resolved;
      case 'cancelled':    return FleetIssueStatus.cancelled;
      default:             return FleetIssueStatus.open;
    }
  }

  String get displayLabel {
    switch (this) {
      case FleetIssueStatus.open:         return 'Open';
      case FleetIssueStatus.acknowledged: return 'Acknowledged';
      case FleetIssueStatus.resolved:     return 'Resolved';
      case FleetIssueStatus.cancelled:    return 'Cancelled';
    }
  }

  bool get isOpen => this == FleetIssueStatus.open || this == FleetIssueStatus.acknowledged;
}

enum FleetIssueShift {
  day('day'),
  night('night'),
  weekend('weekend');

  const FleetIssueShift(this.value);
  final String value;

  static FleetIssueShift fromString(String? value) {
    switch (value) {
      case 'night':   return FleetIssueShift.night;
      case 'weekend': return FleetIssueShift.weekend;
      default:        return FleetIssueShift.day;
    }
  }

  String get displayLabel {
    switch (this) {
      case FleetIssueShift.day:     return 'Day';
      case FleetIssueShift.night:   return 'Night';
      case FleetIssueShift.weekend: return 'Weekend';
    }
  }

  /// Auto-detects shift from current wall-clock time.
  static FleetIssueShift detectFromNow() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return FleetIssueShift.weekend;
    }
    if (now.hour >= 6 && now.hour < 18) return FleetIssueShift.day;
    return FleetIssueShift.night;
  }
}

enum FleetIssueResolutionType {
  workRecord('work_record'),
  note('note');

  const FleetIssueResolutionType(this.value);
  final String value;

  static FleetIssueResolutionType? fromString(String? value) {
    switch (value) {
      case 'work_record': return FleetIssueResolutionType.workRecord;
      case 'note':        return FleetIssueResolutionType.note;
      default:            return null;
    }
  }
}

/// A problem reported on an asset — drives the mechanic's queue.
class FleetIssue {
  final String? id;
  final String assetId;
  final String assetName;
  final String description;
  final FleetIssueSeverity severity;
  final FleetIssueStatus status;
  final String reportedByClockNo;
  final String reportedByName;
  final FleetIssueShift? shift;
  final List<String> parts;
  final List<String> photos;
  final DateTime? createdAt;

  final String? acknowledgedByClockNo;
  final String? acknowledgedByName;
  final DateTime? acknowledgedAt;

  final String? resolvedByClockNo;
  final String? resolvedByName;
  final DateTime? resolvedAt;
  final FleetIssueResolutionType? resolutionType;
  final String? resolutionNote;
  final String? linkedWorkRecordId;

  final String? cancelledByClockNo;
  final String? cancelledByName;
  final DateTime? cancelledAt;
  final String? cancelReason;

  const FleetIssue({
    this.id,
    required this.assetId,
    required this.assetName,
    required this.description,
    required this.severity,
    this.status = FleetIssueStatus.open,
    required this.reportedByClockNo,
    required this.reportedByName,
    this.shift,
    this.parts = const [],
    this.photos = const [],
    this.createdAt,
    this.acknowledgedByClockNo,
    this.acknowledgedByName,
    this.acknowledgedAt,
    this.resolvedByClockNo,
    this.resolvedByName,
    this.resolvedAt,
    this.resolutionType,
    this.resolutionNote,
    this.linkedWorkRecordId,
    this.cancelledByClockNo,
    this.cancelledByName,
    this.cancelledAt,
    this.cancelReason,
  });

  /// "Name (clock)" when both are known, otherwise whichever exists.
  static String? _whoLabel(String? name, String? clockNo) {
    if (name != null && name.isNotEmpty) {
      return clockNo != null && clockNo.isNotEmpty ? '$name ($clockNo)' : name;
    }
    return clockNo;
  }

  String? get acknowledgedByLabel =>
      _whoLabel(acknowledgedByName, acknowledgedByClockNo);
  String? get resolvedByLabel => _whoLabel(resolvedByName, resolvedByClockNo);
  String? get cancelledByLabel =>
      _whoLabel(cancelledByName, cancelledByClockNo);

  factory FleetIssue.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetIssue(
      id: doc.id,
      assetId: data['asset_id'] as String? ?? '',
      assetName: data['asset_name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      severity: FleetIssueSeverity.fromString(data['severity'] as String?),
      status: FleetIssueStatus.fromString(data['status'] as String?),
      reportedByClockNo: data['reported_by_clock_no'] as String? ?? '',
      reportedByName: data['reported_by_name'] as String? ?? '',
      shift: data['shift'] != null
          ? FleetIssueShift.fromString(data['shift'] as String?)
          : null,
      parts: (data['parts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      photos: (data['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      acknowledgedByClockNo: data['acknowledged_by_clock_no'] as String?,
      acknowledgedByName: data['acknowledged_by_name'] as String?,
      acknowledgedAt: (data['acknowledged_at'] as Timestamp?)?.toDate(),
      resolvedByClockNo: data['resolved_by_clock_no'] as String?,
      resolvedByName: data['resolved_by_name'] as String?,
      resolvedAt: (data['resolved_at'] as Timestamp?)?.toDate(),
      resolutionType: FleetIssueResolutionType.fromString(data['resolution_type'] as String?),
      resolutionNote: data['resolution_note'] as String?,
      linkedWorkRecordId: data['linked_work_record_id'] as String?,
      cancelledByClockNo: data['cancelled_by_clock_no'] as String?,
      cancelledByName: data['cancelled_by_name'] as String?,
      cancelledAt: (data['cancelled_at'] as Timestamp?)?.toDate(),
      cancelReason: data['cancel_reason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'asset_id': assetId,
      'asset_name': assetName,
      'description': description,
      'severity': severity.value,
      'status': status.value,
      'reported_by_clock_no': reportedByClockNo,
      'reported_by_name': reportedByName,
      if (shift != null) 'shift': shift!.value,
      if (parts.isNotEmpty) 'parts': parts,
      'photos': photos,
      'created_at': FieldValue.serverTimestamp(),
      if (acknowledgedByClockNo != null) 'acknowledged_by_clock_no': acknowledgedByClockNo,
      if (acknowledgedAt != null) 'acknowledged_at': Timestamp.fromDate(acknowledgedAt!),
      if (resolvedByClockNo != null) 'resolved_by_clock_no': resolvedByClockNo,
      if (resolvedAt != null) 'resolved_at': Timestamp.fromDate(resolvedAt!),
      if (resolutionType != null) 'resolution_type': resolutionType!.value,
      if (resolutionNote != null) 'resolution_note': resolutionNote,
      if (linkedWorkRecordId != null) 'linked_work_record_id': linkedWorkRecordId,
    };
  }

  /// Hours elapsed since issue was created (or null if not yet created).
  double? get ageHours {
    if (createdAt == null) return null;
    return DateTime.now().difference(createdAt!).inMinutes / 60.0;
  }

  FleetIssue copyWith({
    String? id,
    String? assetId,
    String? assetName,
    String? description,
    FleetIssueSeverity? severity,
    FleetIssueStatus? status,
    String? reportedByClockNo,
    String? reportedByName,
    FleetIssueShift? shift,
    List<String>? parts,
    List<String>? photos,
    DateTime? createdAt,
    String? acknowledgedByClockNo,
    String? acknowledgedByName,
    DateTime? acknowledgedAt,
    String? resolvedByClockNo,
    String? resolvedByName,
    DateTime? resolvedAt,
    FleetIssueResolutionType? resolutionType,
    String? resolutionNote,
    String? linkedWorkRecordId,
    String? cancelledByClockNo,
    String? cancelledByName,
    DateTime? cancelledAt,
    String? cancelReason,
  }) {
    return FleetIssue(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      assetName: assetName ?? this.assetName,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      reportedByClockNo: reportedByClockNo ?? this.reportedByClockNo,
      reportedByName: reportedByName ?? this.reportedByName,
      shift: shift ?? this.shift,
      parts: parts ?? this.parts,
      photos: photos ?? this.photos,
      createdAt: createdAt ?? this.createdAt,
      acknowledgedByClockNo: acknowledgedByClockNo ?? this.acknowledgedByClockNo,
      acknowledgedByName: acknowledgedByName ?? this.acknowledgedByName,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      resolvedByClockNo: resolvedByClockNo ?? this.resolvedByClockNo,
      resolvedByName: resolvedByName ?? this.resolvedByName,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolutionType: resolutionType ?? this.resolutionType,
      resolutionNote: resolutionNote ?? this.resolutionNote,
      linkedWorkRecordId: linkedWorkRecordId ?? this.linkedWorkRecordId,
      cancelledByClockNo: cancelledByClockNo ?? this.cancelledByClockNo,
      cancelledByName: cancelledByName ?? this.cancelledByName,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
    );
  }
}
