import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/fleet_soft_delete.dart';

/// A maintenance or repair job logged by the Hyster mechanic.
class FleetWorkRecord {

  final String? id;
  final String workNumber;
  final String assetId;
  final String assetName;
  final String workTypeId;
  final String workTypeName;
  final String title;
  final String description;
  final double labourHours;
  final double? machineHoursReading;
  final List<String> photos;
  final DateTime startDate;
  final DateTime endDate;
  final String loggedByClockNo;
  final String loggedByName;
  final DateTime? createdAt;
  final List<String> linkedIssueIds;
  final bool hasLinkedCosts;

  /// Hidden from mobile/Pulse lists when an admin soft-deletes on Pulse.
  final bool isDeleted;

  /// Days a mechanic may edit a record after it was created.
  static const int editLockDays = 7;

  const FleetWorkRecord({
    this.id,
    required this.workNumber,
    required this.assetId,
    required this.assetName,
    required this.workTypeId,
    required this.workTypeName,
    required this.title,
    required this.description,
    required this.labourHours,
    this.machineHoursReading,
    this.photos = const [],
    required this.startDate,
    required this.endDate,
    required this.loggedByClockNo,
    required this.loggedByName,
    this.createdAt,
    this.linkedIssueIds = const [],
    this.hasLinkedCosts = false,
    this.isDeleted = false,
  });

  /// Whether the record is still inside the [editLockDays] window.
  /// Records with no server timestamp yet are treated as not locked.
  bool get isWithinEditWindow {
    final created = createdAt;
    if (created == null) return true;
    return DateTime.now().difference(created).inDays < editLockDays;
  }

  bool get isEditLocked => !isWithinEditWindow;

  /// Edit rule shared across screens: admins always; mechanics only
  /// while no costs are linked and inside the edit window.
  bool canEdit({required bool isMechanic, required bool isAdmin}) {
    if (isAdmin) return true;
    return isMechanic && !hasLinkedCosts && isWithinEditWindow;
  }

  /// Supplementary comments on the fix — allowed within [editLockDays] from
  /// [createdAt] even when [hasLinkedCosts] blocks field edits.
  bool canAddComment({required bool isMechanic, required bool isAdmin}) {
    if (isAdmin) return true;
    if (!isMechanic) return false;
    return isWithinCommentWindow;
  }

  /// Same 7-day window as edit, but ignores linked costs.
  bool get isWithinCommentWindow {
    final created = createdAt;
    if (created == null) return true;
    return DateTime.now().difference(created).inDays < editLockDays;
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      final parsed = DateTime.tryParse(
          value.length == 10 ? '${value}T00:00:00' : value);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  static bool _parseHasLinkedCosts(Map<String, dynamic> data) {
    if (data['has_linked_costs'] == true) return true;
    // Legacy fields from pre-greenfield pilot data.
    if (data['has_cost_lines'] == true) return true;
    final status = data['cost_status'] as String?;
    return status == 'costed';
  }

  factory FleetWorkRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FleetWorkRecord(
      id: doc.id,
      workNumber: data['work_number'] as String? ?? '',
      assetId: data['asset_id'] as String? ?? '',
      assetName: data['asset_name'] as String? ?? '',
      workTypeId: data['work_type_id'] as String? ?? '',
      workTypeName: data['work_type_name'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      labourHours: (data['labour_hours'] as num?)?.toDouble() ?? 0.0,
      machineHoursReading: (data['machine_hours_reading'] as num?)?.toDouble(),
      photos: (data['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      startDate: _parseDate(data['start_date']),
      endDate: _parseDate(data['end_date']),
      loggedByClockNo: data['logged_by_clock_no'] as String? ?? '',
      loggedByName: data['logged_by_name'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      linkedIssueIds: (data['linked_issue_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      hasLinkedCosts: _parseHasLinkedCosts(data),
      isDeleted: parseFleetDeleted(data),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'work_number': workNumber,
      'asset_id': assetId,
      'asset_name': assetName,
      'work_type_id': workTypeId,
      'work_type_name': workTypeName,
      'title': title,
      'description': description,
      'labour_hours': labourHours,
      if (machineHoursReading != null) 'machine_hours_reading': machineHoursReading,
      'photos': photos,
      'start_date': Timestamp.fromDate(startDate),
      'end_date': Timestamp.fromDate(endDate),
      'logged_by_clock_no': loggedByClockNo,
      'logged_by_name': loggedByName,
      'linked_issue_ids': linkedIssueIds,
      if (hasLinkedCosts) 'has_linked_costs': true,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  FleetWorkRecord copyWith({
    String? id,
    String? workNumber,
    String? assetId,
    String? assetName,
    String? workTypeId,
    String? workTypeName,
    String? title,
    String? description,
    double? labourHours,
    double? machineHoursReading,
    List<String>? photos,
    DateTime? startDate,
    DateTime? endDate,
    String? loggedByClockNo,
    String? loggedByName,
    DateTime? createdAt,
    List<String>? linkedIssueIds,
    bool? hasLinkedCosts,
    bool? isDeleted,
  }) {
    return FleetWorkRecord(
      id: id ?? this.id,
      workNumber: workNumber ?? this.workNumber,
      assetId: assetId ?? this.assetId,
      assetName: assetName ?? this.assetName,
      workTypeId: workTypeId ?? this.workTypeId,
      workTypeName: workTypeName ?? this.workTypeName,
      title: title ?? this.title,
      description: description ?? this.description,
      labourHours: labourHours ?? this.labourHours,
      machineHoursReading: machineHoursReading ?? this.machineHoursReading,
      photos: photos ?? this.photos,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      loggedByClockNo: loggedByClockNo ?? this.loggedByClockNo,
      loggedByName: loggedByName ?? this.loggedByName,
      createdAt: createdAt ?? this.createdAt,
      linkedIssueIds: linkedIssueIds ?? this.linkedIssueIds,
      hasLinkedCosts: hasLinkedCosts ?? this.hasLinkedCosts,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}