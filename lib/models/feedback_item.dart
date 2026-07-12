import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared feedback domain model — used by the admin triage board
/// (feedback_admin_screen.dart), the worker-facing My Feedback list
/// (my_feedback_screen.dart) and the two-way thread view
/// (feedback_thread_screen.dart).
///
/// Lifecycle: a worker submits feedback from the home-screen FAB; an admin
/// triages it New → Planned → Implemented → Declined and can post PUBLIC
/// replies into the `feedback_comments` subcollection (visible to the
/// submitter, who can reply back). `adminNotes` stays a PRIVATE admin-only
/// field and never appears in the thread. Cloud Functions close the loop by
/// notifying the submitter on status changes / admin replies and notifying
/// admins on submitter replies.
enum FeedbackStatus { newItem, planned, implemented, declined }

extension FeedbackStatusX on FeedbackStatus {
  /// Stable id persisted to Firestore (`status` field).
  String get id {
    switch (this) {
      case FeedbackStatus.newItem:
        return 'new';
      case FeedbackStatus.planned:
        return 'planned';
      case FeedbackStatus.implemented:
        return 'implemented';
      case FeedbackStatus.declined:
        return 'declined';
    }
  }

  String get label {
    switch (this) {
      case FeedbackStatus.newItem:
        return 'New';
      case FeedbackStatus.planned:
        return 'Planned';
      case FeedbackStatus.implemented:
        return 'Implemented';
      case FeedbackStatus.declined:
        return 'Declined';
    }
  }

  /// Worker-facing wording — "New" reads oddly on your own submission.
  String get workerLabel {
    switch (this) {
      case FeedbackStatus.newItem:
        return 'Received';
      case FeedbackStatus.planned:
        return 'Planned';
      case FeedbackStatus.implemented:
        return 'Done';
      case FeedbackStatus.declined:
        return 'Declined';
    }
  }

  /// Maps a persisted id back to the enum; missing/unknown → New so legacy
  /// feedback docs (created before triage existed) show as untriaged.
  static FeedbackStatus fromId(String? id) {
    switch (id) {
      case 'planned':
        return FeedbackStatus.planned;
      case 'implemented':
        return FeedbackStatus.implemented;
      case 'declined':
        return FeedbackStatus.declined;
      default:
        return FeedbackStatus.newItem;
    }
  }
}

Color feedbackStatusColor(BuildContext context, FeedbackStatus s) {
  final c = Theme.of(context).appColors;
  switch (s) {
    case FeedbackStatus.newItem:
      return c.statusOpen; // blue — untriaged, needs attention
    case FeedbackStatus.planned:
      return kBrandOrange; // orange — on the roadmap
    case FeedbackStatus.implemented:
      return c.wasteGreen; // green — done
    case FeedbackStatus.declined:
      return c.textMuted; // grey — won't do
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

/// Parsed view of a `feedback` document, tolerant of legacy docs that predate
/// the triage fields (`status`, `adminNotes`, …).
class FeedbackItem {
  final String id;
  final String feedback;
  final String userName;
  final String clockNo;
  final DateTime? submittedAt;
  final FeedbackStatus status;
  final String notes;
  final DateTime? notesUpdatedAt;
  final DateTime? lastCommentAt;
  final int commentCount;
  /// Download URLs for photos attached at submit time (optional).
  final List<String> photoUrls;

  FeedbackItem({
    required this.id,
    required this.feedback,
    required this.userName,
    required this.clockNo,
    required this.submittedAt,
    required this.status,
    required this.notes,
    required this.notesUpdatedAt,
    required this.lastCommentAt,
    required this.commentCount,
    this.photoUrls = const [],
  });

  factory FeedbackItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return FeedbackItem(
      id: doc.id,
      feedback: (data['feedback'] as String?)?.trim() ?? '',
      userName: (data['userName'] as String?)?.trim() ?? '',
      clockNo: (data['clockNo'] as String?)?.trim() ?? '',
      submittedAt: ts(data['timestamp']),
      status: FeedbackStatusX.fromId(data['status'] as String?),
      notes: (data['adminNotes'] as String?) ?? '',
      notesUpdatedAt: ts(data['adminNotesUpdatedAt']),
      // Maintained server-side by the onFeedbackCommentCreated CF.
      lastCommentAt: ts(data['lastCommentAt']),
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      photoUrls: _parsePhotoUrls(data['photoUrls']),
    );
  }
}

/// One message in the public feedback thread
/// (`feedback/{id}/feedback_comments/{autoId}`).
class FeedbackComment {
  final String id;
  final String text;
  final String byClockNo;
  final String byName;
  final bool byIsAdmin;
  final DateTime? createdAt;
  /// Download URLs for photos attached to this reply (optional).
  final List<String> photoUrls;

  FeedbackComment({
    required this.id,
    required this.text,
    required this.byClockNo,
    required this.byName,
    required this.byIsAdmin,
    required this.createdAt,
    this.photoUrls = const [],
  });

  factory FeedbackComment.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FeedbackComment(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      byClockNo: (data['byClockNo'] as String?) ?? '',
      byName: (data['byName'] as String?) ?? '',
      byIsAdmin: data['byIsAdmin'] == true,
      createdAt:
          data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
      photoUrls: _parsePhotoUrls(data['photoUrls']),
    );
  }
}
