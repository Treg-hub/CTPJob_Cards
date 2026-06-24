import 'package:cloud_firestore/cloud_firestore.dart';

/// One row on the daily forklift checklist (snapshot at start submit).
class FleetDailyCheckItem {
  final String id;
  final String label;
  final String result; // 'ok' | 'faulty'
  final bool reviewed;

  const FleetDailyCheckItem({
    required this.id,
    required this.label,
    this.result = 'faulty',
    this.reviewed = false,
  });

  bool get isOk => result == 'ok';
  bool get isFaulty => result == 'faulty';

  factory FleetDailyCheckItem.fromMap(Map<String, dynamic> data) {
    return FleetDailyCheckItem(
      id: data['id']?.toString() ?? '',
      label: data['label'] as String? ?? '',
      result: data['result'] as String? ?? 'faulty',
      reviewed: data['reviewed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'result': result,
        'reviewed': reviewed,
      };

  FleetDailyCheckItem copyWith({
    String? id,
    String? label,
    String? result,
    bool? reviewed,
  }) {
    return FleetDailyCheckItem(
      id: id ?? this.id,
      label: label ?? this.label,
      result: result ?? this.result,
      reviewed: reviewed ?? this.reviewed,
    );
  }
}

class FleetDailyCheckStart {
  final DateTime? at;
  final double hourMeter;
  final String driverClockNo;
  final String driverName;
  final String? department;
  final List<FleetDailyCheckItem> items;
  final String? generalComment;

  const FleetDailyCheckStart({
    this.at,
    required this.hourMeter,
    required this.driverClockNo,
    required this.driverName,
    this.department,
    required this.items,
    this.generalComment,
  });

  factory FleetDailyCheckStart.fromMap(Map<String, dynamic> data) {
    final rawItems = data['items'] as List<dynamic>? ?? [];
    return FleetDailyCheckStart(
      at: _parseTimestamp(data['at']),
      hourMeter: (data['hour_meter'] as num?)?.toDouble() ?? 0,
      driverClockNo: data['driver_clock_no'] as String? ?? '',
      driverName: data['driver_name'] as String? ?? '',
      department: data['department'] as String?,
      items: rawItems
          .map((e) =>
              FleetDailyCheckItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      generalComment: data['general_comment'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'at': at != null ? Timestamp.fromDate(at!) : FieldValue.serverTimestamp(),
        'hour_meter': hourMeter,
        'driver_clock_no': driverClockNo,
        'driver_name': driverName,
        if (department != null) 'department': department,
        'items': items.map((i) => i.toMap()).toList(),
        if (generalComment != null && generalComment!.isNotEmpty)
          'general_comment': generalComment,
      };
}

class FleetDailyCheckEnd {
  final DateTime? at;
  final double hourMeter;
  final String? comment;

  const FleetDailyCheckEnd({
    this.at,
    required this.hourMeter,
    this.comment,
  });

  factory FleetDailyCheckEnd.fromMap(Map<String, dynamic> data) {
    return FleetDailyCheckEnd(
      at: _parseTimestamp(data['at']),
      hourMeter: (data['hour_meter'] as num?)?.toDouble() ?? 0,
      comment: data['comment'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'at': at != null ? Timestamp.fromDate(at!) : FieldValue.serverTimestamp(),
        'hour_meter': hourMeter,
        if (comment != null && comment!.isNotEmpty) 'comment': comment,
      };
}

/// Daily forklift pre-use check — doc id `{assetId}_{YYYY-MM-DD}`.
class FleetDailyCheck {
  final String? id;
  final String assetId;
  final String assetName;
  final String assetTag;
  final String checkDate;
  final FleetDailyCheckStart? start;
  final FleetDailyCheckEnd? end;
  final bool hasFaultyItems;
  final double? hoursUsed;
  final String? clientRef;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FleetDailyCheck({
    this.id,
    required this.assetId,
    required this.assetName,
    required this.assetTag,
    required this.checkDate,
    this.start,
    this.end,
    this.hasFaultyItems = false,
    this.hoursUsed,
    this.clientRef,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasStart => start != null;
  bool get hasEnd => end != null;
  bool get isOpen => hasStart && !hasEnd;

  int get faultyCount =>
      start?.items.where((i) => i.isFaulty).length ?? 0;

  factory FleetDailyCheck.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetDailyCheck(
      id: doc.id,
      assetId: data['asset_id'] as String? ?? '',
      assetName: data['asset_name'] as String? ?? '',
      assetTag: data['asset_tag'] as String? ?? '',
      checkDate: data['check_date'] as String? ?? '',
      start: data['start'] != null
          ? FleetDailyCheckStart.fromMap(
              Map<String, dynamic>.from(data['start'] as Map))
          : null,
      end: data['end'] != null
          ? FleetDailyCheckEnd.fromMap(
              Map<String, dynamic>.from(data['end'] as Map))
          : null,
      hasFaultyItems: data['has_faulty_items'] as bool? ?? false,
      hoursUsed: (data['hours_used'] as num?)?.toDouble(),
      clientRef: data['client_ref'] as String?,
      createdAt: _parseTimestamp(data['created_at']),
      updatedAt: _parseTimestamp(data['updated_at']),
    );
  }

  static String docIdFor(String assetId, [DateTime? date]) {
    final d = date ?? DateTime.now();
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${assetId}_$day';
  }

  static String checkDateString([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

DateTime? _parseTimestamp(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}