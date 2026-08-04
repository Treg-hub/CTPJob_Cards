import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Admin walkaround / park-for-later note (`system_review_notes`).
///
/// Captured on the phone while walking the floor (isAdmin only). Reviewed later
/// to decide how (or whether) the idea fits the CTP factory ecosystem. Not part
/// of the staff feedback loop — no submitter notifications, no public thread.
///
/// Body (`text`) is cumulative: use **Add more detail** to append dated
/// observations when you find extra information later. `heading` is the short
/// title for scanning the list.
enum SystemReviewNoteStatus {
  open,
  reviewing,
  actioned,
  parked,
  dropped,
}

extension SystemReviewNoteStatusX on SystemReviewNoteStatus {
  String get id {
    switch (this) {
      case SystemReviewNoteStatus.open:
        return 'open';
      case SystemReviewNoteStatus.reviewing:
        return 'reviewing';
      case SystemReviewNoteStatus.actioned:
        return 'actioned';
      case SystemReviewNoteStatus.parked:
        return 'parked';
      case SystemReviewNoteStatus.dropped:
        return 'dropped';
    }
  }

  String get label {
    switch (this) {
      case SystemReviewNoteStatus.open:
        return 'Open';
      case SystemReviewNoteStatus.reviewing:
        return 'Reviewing';
      case SystemReviewNoteStatus.actioned:
        return 'Actioned';
      case SystemReviewNoteStatus.parked:
        return 'Parked';
      case SystemReviewNoteStatus.dropped:
        return 'Dropped';
    }
  }

  static SystemReviewNoteStatus fromId(String? id) {
    switch (id) {
      case 'reviewing':
        return SystemReviewNoteStatus.reviewing;
      case 'actioned':
        return SystemReviewNoteStatus.actioned;
      case 'parked':
        return SystemReviewNoteStatus.parked;
      case 'dropped':
        return SystemReviewNoteStatus.dropped;
      default:
        return SystemReviewNoteStatus.open;
    }
  }
}

Color systemReviewNoteStatusColor(BuildContext context, SystemReviewNoteStatus s) {
  final c = Theme.of(context).appColors;
  switch (s) {
    case SystemReviewNoteStatus.open:
      return c.statusOpen;
    case SystemReviewNoteStatus.reviewing:
      return kBrandOrange;
    case SystemReviewNoteStatus.actioned:
      return c.wasteGreen;
    case SystemReviewNoteStatus.parked:
      return Colors.deepPurple.shade400;
    case SystemReviewNoteStatus.dropped:
      return c.textMuted;
  }
}

/// Optional module tags for consolidating walk notes later.
const List<String> kSystemReviewModules = [
  'Ink',
  'Fleet',
  'Waste',
  'Security',
  'Lurgi',
  'Stores',
  'Job Cards',
  'Pulse',
  'Platform',
  'Other',
];

List<String> _parsePhotoUrls(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList();
}

class SystemReviewNote {
  final String id;
  /// Short title for list scanning (optional; falls back to module / first line).
  final String heading;
  final String text;
  final String module;
  final String area;
  final SystemReviewNoteStatus status;
  final String createdByClockNo;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String reviewNotes;
  final DateTime? reviewNotesUpdatedAt;
  final List<String> photoUrls;

  SystemReviewNote({
    required this.id,
    required this.heading,
    required this.text,
    required this.module,
    required this.area,
    required this.status,
    required this.createdByClockNo,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewNotes,
    required this.reviewNotesUpdatedAt,
    required this.photoUrls,
  });

  /// Card / list title: heading, else module, else truncated body.
  String get displayTitle {
    if (heading.isNotEmpty) return heading;
    if (module.isNotEmpty) return module;
    if (text.isNotEmpty) {
      final line = text.split('\n').first.trim();
      if (line.length <= 48) return line;
      return '${line.substring(0, 45)}…';
    }
    return 'Walk note';
  }

  factory SystemReviewNote.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? ts;
    final rawTs = data['createdAt'];
    if (rawTs is Timestamp) ts = rawTs.toDate();
    DateTime? updated;
    final rawUpdated = data['updatedAt'];
    if (rawUpdated is Timestamp) updated = rawUpdated.toDate();
    DateTime? notesAt;
    final rawNotesAt = data['reviewNotesUpdatedAt'];
    if (rawNotesAt is Timestamp) notesAt = rawNotesAt.toDate();

    return SystemReviewNote(
      id: doc.id,
      heading: (data['heading'] as String?)?.trim() ?? '',
      text: (data['text'] as String?)?.trim() ?? '',
      module: (data['module'] as String?)?.trim() ?? '',
      area: (data['area'] as String?)?.trim() ?? '',
      status: SystemReviewNoteStatusX.fromId(data['status'] as String?),
      createdByClockNo: (data['createdByClockNo'] as String?)?.trim() ?? '',
      createdByName: (data['createdByName'] as String?)?.trim() ?? '',
      createdAt: ts,
      updatedAt: updated,
      reviewNotes: (data['reviewNotes'] as String?)?.trim() ?? '',
      reviewNotesUpdatedAt: notesAt,
      photoUrls: _parsePhotoUrls(data['photoUrls']),
    );
  }
}
