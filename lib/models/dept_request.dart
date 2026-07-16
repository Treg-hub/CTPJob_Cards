import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Lifecycle for manager-to-manager [DeptRequest] docs.
enum DeptRequestStatus { open, acknowledged, done, withdrawn }

extension DeptRequestStatusX on DeptRequestStatus {
  String get id {
    switch (this) {
      case DeptRequestStatus.open:
        return 'open';
      case DeptRequestStatus.acknowledged:
        return 'acknowledged';
      case DeptRequestStatus.done:
        return 'done';
      case DeptRequestStatus.withdrawn:
        return 'withdrawn';
    }
  }

  String get label {
    switch (this) {
      case DeptRequestStatus.open:
        return 'Open';
      case DeptRequestStatus.acknowledged:
        return 'Acknowledged';
      case DeptRequestStatus.done:
        return 'Done';
      case DeptRequestStatus.withdrawn:
        return 'Withdrawn';
    }
  }

  static DeptRequestStatus fromId(String? id) {
    switch (id) {
      case 'acknowledged':
        return DeptRequestStatus.acknowledged;
      case 'done':
        return DeptRequestStatus.done;
      case 'withdrawn':
        return DeptRequestStatus.withdrawn;
      default:
        return DeptRequestStatus.open;
    }
  }
}

Color deptRequestStatusColor(BuildContext context, DeptRequestStatus s) {
  final c = Theme.of(context).appColors;
  switch (s) {
    case DeptRequestStatus.open:
      return c.statusOpen;
    case DeptRequestStatus.acknowledged:
      return kBrandOrange;
    case DeptRequestStatus.done:
      return c.wasteGreen;
    case DeptRequestStatus.withdrawn:
      return c.textMuted;
  }
}

List<String> _parsePhotoUrls(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList();
}

/// Parsed `dept_requests/{id}` document.
class DeptRequest {
  final String id;
  final String requestNumber;
  final String message;
  final List<String> photoUrls;
  final String fromDepartment;
  final String targetDepartment;
  final String area;
  final String locationPath;
  final DeptRequestStatus status;
  final String createdByClockNo;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;
  final DateTime? lastCommentAt;
  final int commentCount;
  final String? acknowledgedByClockNo;
  final DateTime? acknowledgedAt;
  final String? doneByClockNo;
  final String? doneNote;
  final DateTime? doneAt;

  const DeptRequest({
    required this.id,
    required this.requestNumber,
    required this.message,
    required this.photoUrls,
    required this.fromDepartment,
    required this.targetDepartment,
    required this.area,
    required this.locationPath,
    required this.status,
    required this.createdByClockNo,
    required this.createdByName,
    required this.createdAt,
    required this.lastActivityAt,
    required this.lastCommentAt,
    required this.commentCount,
    this.acknowledgedByClockNo,
    this.acknowledgedAt,
    this.doneByClockNo,
    this.doneNote,
    this.doneAt,
  });

  bool get isActive =>
      status == DeptRequestStatus.open ||
      status == DeptRequestStatus.acknowledged;

  /// Soft cue: open/acked longer than 48 hours.
  bool get isOpenOver48h {
    if (!isActive || createdAt == null) return false;
    return DateTime.now().difference(createdAt!) > const Duration(hours: 48);
  }

  factory DeptRequest.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final target = (data['targetDepartment'] as String?)?.trim() ?? '';
    final area = (data['area'] as String?)?.trim() ?? '';
    final path = (data['locationPath'] as String?)?.trim();
    return DeptRequest(
      id: doc.id,
      requestNumber: (data['requestNumber'] as String?)?.trim() ?? '',
      message: (data['message'] as String?)?.trim() ?? '',
      photoUrls: _parsePhotoUrls(data['photoUrls']),
      fromDepartment: (data['fromDepartment'] as String?)?.trim() ?? '',
      targetDepartment: target,
      area: area,
      locationPath: (path != null && path.isNotEmpty)
          ? path
          : (area.isEmpty ? target : '$target > $area'),
      status: DeptRequestStatusX.fromId(data['status'] as String?),
      createdByClockNo: (data['createdByClockNo'] as String?)?.trim() ?? '',
      createdByName: (data['createdByName'] as String?)?.trim() ?? '',
      createdAt: ts(data['createdAt']),
      lastActivityAt: ts(data['lastActivityAt']) ?? ts(data['createdAt']),
      lastCommentAt: ts(data['lastCommentAt']),
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      acknowledgedByClockNo:
          (data['acknowledgedByClockNo'] as String?)?.trim(),
      acknowledgedAt: ts(data['acknowledgedAt']),
      doneByClockNo: (data['doneByClockNo'] as String?)?.trim(),
      doneNote: (data['doneNote'] as String?)?.trim(),
      doneAt: ts(data['doneAt']),
    );
  }
}

/// One message in `dept_requests/{id}/comments/{id}`.
class DeptRequestComment {
  final String id;
  final String text;
  final String byClockNo;
  final String byName;
  final DateTime? createdAt;
  final List<String> photoUrls;

  const DeptRequestComment({
    required this.id,
    required this.text,
    required this.byClockNo,
    required this.byName,
    required this.createdAt,
    this.photoUrls = const [],
  });

  factory DeptRequestComment.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return DeptRequestComment(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      byClockNo: (data['byClockNo'] as String?) ?? '',
      byName: (data['byName'] as String?) ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      photoUrls: _parsePhotoUrls(data['photoUrls']),
    );
  }
}
