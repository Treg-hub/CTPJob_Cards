import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show realEmployee;
import '../services/firestore_service.dart';
import '../widgets/ctp_app_bar.dart';
import '../utils/fleet_navigation.dart';
import 'feedback_thread_screen.dart';
import 'job_card_detail_screen.dart';
import '../utils/screen_insets.dart';

// ---------------------------------------------------------------------------
// NotificationInboxScreen
// Shows notifications that were parked because the user was offsite.
// ---------------------------------------------------------------------------

class NotificationInboxScreen extends ConsumerStatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  ConsumerState<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState
    extends ConsumerState<NotificationInboxScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _markingAllRead = false;

  CollectionReference<Map<String, dynamic>>? get _itemsRef {
    final clockNo = realEmployee?.clockNo;
    if (clockNo == null) return null;
    return FirebaseFirestore.instance
        .collection('notification_inbox')
        .doc(clockNo)
        .collection('items');
  }

  Future<void> _markRead(String docId) async {
    final ref = _itemsRef;
    if (ref == null) return;
    await ref.doc(docId).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markAllRead(List<QueryDocumentSnapshot> unreadDocs) async {
    if (unreadDocs.isEmpty) return;
    setState(() => _markingAllRead = true);
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unreadDocs) {
      batch.update(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (mounted) setState(() => _markingAllRead = false);
  }

  Future<void> _openNotificationTarget(
    BuildContext ctx,
    Map<String, dynamic> data,
  ) async {
    final issueId = data['issueId'] as String?;
    final type = data['type'] as String? ?? '';
    if (issueId != null &&
        issueId.isNotEmpty &&
        type.startsWith('fleet_')) {
      await openFleetIssue(ctx, issueId);
      return;
    }

    final feedbackId = data['feedbackId'] as String?;
    if (feedbackId != null && feedbackId.isNotEmpty && type.startsWith('feedback')) {
      await Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => FeedbackThreadScreen(feedbackId: feedbackId)),
      );
      return;
    }

    final jobCardId = data['jobCardId'] as String?;
    if (jobCardId == null || jobCardId.isEmpty) return;
    try {
      final job = await _firestoreService.getJobCard(jobCardId);
      if (job != null && ctx.mounted) {
        Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Could not open job card: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clockNo = realEmployee?.clockNo;
    if (clockNo == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: const CtpAppBar(title: 'Notification Inbox'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _itemsRef!
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          final unread = docs.where((d) => d.data()['read'] != true).toList();
          final read = docs.where((d) => d.data()['read'] == true).toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green.shade400),
                  const SizedBox(height: 12),
                  const Text("You're all caught up",
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('No pending notifications',
                      style: TextStyle(
                          color: const Color(0xFF616161), fontSize: 14)),
                ],
              ),
            );
          }

          return Column(
            children: [
              if (unread.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${unread.length} Unread',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      TextButton.icon(
                        onPressed: _markingAllRead
                            ? null
                            : () => _markAllRead(unread),
                        icon: _markingAllRead
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.done_all, size: 16),
                        label: const Text('Mark all read'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF8C42),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: ScreenInsets.listPadding(context, horizontal: 12, top: 8),
                  children: [
                    ...unread.map((doc) => _NotifTile(
                          doc: doc,
                          onTap: () async {
                            await _markRead(doc.id);
                            if (context.mounted) {
                              await _openNotificationTarget(
                                  context, doc.data());
                            }
                          },
                          onMarkRead: () => _markRead(doc.id),
                        )),
                    if (read.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text(
                          'Earlier',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF757575),
                              letterSpacing: 0.5),
                        ),
                      ),
                      ...read.map((doc) => _NotifTile(
                            doc: doc,
                            onTap: () => _openNotificationTarget(
                                context, doc.data()),
                            onMarkRead: null,
                          )),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual notification tile
// ---------------------------------------------------------------------------

class _NotifTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;

  const _NotifTile({
    required this.doc,
    required this.onTap,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final isUnread = data['read'] != true;
    final title = data['title'] as String? ?? 'Notification';
    final body = data['body'] as String? ?? '';
    final type = data['type'] as String? ?? '';
    final initiatedBy = data['initiatedByName'] as String?;
    final createdAt = data['createdAt'];

    String timeStr = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      final now = DateTime.now();
      if (now.difference(dt).inDays < 1) {
        timeStr = DateFormat.jm().format(dt);
      } else if (now.difference(dt).inDays < 7) {
        timeStr = DateFormat('EEE, HH:mm').format(dt);
      } else {
        timeStr = DateFormat('d MMM').format(dt);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isUnread
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isUnread
            ? BorderSide(
                color: const Color(0xFFFF8C42).withValues(alpha: 0.4), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _typeColor(type).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_typeIcon(type),
                    size: 20, color: _typeColor(type)),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Text(timeStr,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF757575))),
                      ],
                    ),
                    if (body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          body,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF424242)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (initiatedBy != null && initiatedBy.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'From: $initiatedBy',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF757575)),
                        ),
                      ),
                  ],
                ),
              ),
              // Unread dot or mark-read button
              if (isUnread && onMarkRead != null)
                Column(
                  children: [
                    const SizedBox(height: 2),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF8C42),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'job_assigned':
      case 'assignment_callable':
        return Icons.assignment_ind;
      case 'job_closed':
        return Icons.check_circle;
      case 'self_assigned':
        return Icons.person_add;
      case 'job_updated':
        return Icons.edit_note;
      case 'busy_response':
        return Icons.do_not_disturb_on;
      case 'copper_sell':
        return Icons.monetization_on;
      case 'fleet_oos_issue':
        return Icons.warning_amber_rounded;
      case 'fleet_high_issue':
      case 'fleet_medium_issue':
      case 'fleet_low_issue':
      case 'fleet_daily_check_issue':
      case 'fleet_issue':
        return Icons.build_circle_outlined;
      case 'fleet_issue_resolved':
        return Icons.check_circle_outline;
      case 'feedback_comment':
        return Icons.forum;
      case 'feedback_status':
        return Icons.fact_check_outlined;
      default:
        return Icons.notifications;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'job_assigned':
      case 'assignment_callable':
        return Colors.blue;
      case 'job_closed':
        return Colors.green;
      case 'self_assigned':
        return Colors.teal;
      case 'job_updated':
        return Colors.deepOrange;
      case 'busy_response':
        return Colors.red;
      case 'copper_sell':
        return Colors.amber.shade700;
      case 'fleet_oos_issue':
        return Colors.red.shade700;
      case 'fleet_high_issue':
        return Colors.orange.shade800;
      case 'fleet_medium_issue':
      case 'fleet_low_issue':
      case 'fleet_daily_check_issue':
      case 'fleet_issue':
        return const Color(0xFF2A9D9F);
      case 'fleet_issue_resolved':
        return Colors.green.shade700;
      case 'feedback_comment':
        return const Color(0xFFFF8C42);
      case 'feedback_status':
        return Colors.teal;
      default:
        return const Color(0xFFFF8C42);
    }
  }
}
