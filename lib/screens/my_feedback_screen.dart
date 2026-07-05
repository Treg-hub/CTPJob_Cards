import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/collections.dart';
import '../main.dart' show realEmployee;
import '../models/feedback_item.dart';
import '../theme/app_theme.dart';
import '../widgets/ctp_app_bar.dart';
import '../utils/persona_audit.dart';
import 'feedback_thread_screen.dart';

/// Worker-facing feedback home: submit new feedback and follow what happened
/// to previous submissions (status + public replies from the team).
///
/// Opened from the home-screen feedback FAB. Lists only the signed-in
/// employee's own items (query by clockNo); tapping one opens the two-way
/// thread. Statuses use worker-friendly wording (Received/Planned/Done).
class MyFeedbackScreen extends StatefulWidget {
  const MyFeedbackScreen({super.key});

  @override
  State<MyFeedbackScreen> createState() => _MyFeedbackScreenState();
}

class _MyFeedbackScreenState extends State<MyFeedbackScreen> {
  Future<void> _showFeedbackDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What improvements would you like to see?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type your feedback here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange, foregroundColor: Colors.white),
            onPressed: () async {
              final feedback = controller.text.trim();
              if (feedback.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter some feedback')),
                );
                return;
              }
              if (!guardPersonaSubmit(ctx)) return;
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final session = writeAttributionEmployee ?? realEmployee;
              try {
                await FirebaseFirestore.instance.collection(Collections.feedback).add({
                  'feedback': feedback,
                  'userName': session?.name ?? 'Unknown',
                  'clockNo': session?.clockNo ?? 'Unknown',
                  'timestamp': FieldValue.serverTimestamp(),
                  ...personaAuditFields(),
                });
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Thank you! Your feedback has been submitted.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                      content: Text('Error submitting feedback: $e'),
                      backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final clockNo = realEmployee?.clockNo;
    return Scaffold(
      appBar: const CtpAppBar(title: 'My Feedback'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showFeedbackDialog,
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Give Feedback'),
      ),
      body: clockNo == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // No orderBy: equality-filter-only query needs no composite
              // index; per-user volume is small, so sort client-side.
              stream: FirebaseFirestore.instance
                  .collection(Collections.feedback)
                  .where('clockNo', isEqualTo: clockNo)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error loading feedback: ${snap.error}'));
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = (snap.data?.docs ?? []).map(FeedbackItem.fromDoc).toList()
                  ..sort((a, b) {
                    final at = a.submittedAt ?? DateTime(2000);
                    final bt = b.submittedAt ?? DateTime(2000);
                    return bt.compareTo(at);
                  });
                if (items.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.feedback_outlined, size: 48, color: colors.textMuted),
                      const SizedBox(height: 12),
                      Text('Nothing here yet', style: TextStyle(color: colors.textMuted)),
                      const SizedBox(height: 4),
                      Text('Tell us what to improve — we reply here.',
                          style: TextStyle(color: colors.textMuted, fontSize: 12)),
                    ]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _feedbackCard(items[i], colors),
                );
              },
            ),
    );
  }

  Widget _feedbackCard(FeedbackItem item, AppColors colors) {
    final fmt = DateFormat('d MMM yyyy');
    final statusColor = feedbackStatusColor(context, item.status);
    final hasReplies = item.commentCount > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.cardSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FeedbackThreadScreen(feedbackId: item.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.status.workerLabel,
                  style:
                      TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
              const Spacer(),
              if (item.submittedAt != null)
                Text(fmt.format(item.submittedAt!),
                    style: TextStyle(fontSize: 11, color: colors.textMuted)),
            ]),
            const SizedBox(height: 8),
            Text(
              item.feedback.isEmpty ? '(empty)' : item.feedback,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(hasReplies ? Icons.forum : Icons.forum_outlined,
                  size: 14, color: hasReplies ? kBrandOrange : colors.textMuted),
              const SizedBox(width: 4),
              Text(
                hasReplies
                    ? '${item.commentCount} ${item.commentCount == 1 ? 'reply' : 'replies'}'
                    : 'No replies yet',
                style: TextStyle(
                    fontSize: 12,
                    color: hasReplies ? kBrandOrange : colors.textMuted,
                    fontWeight: hasReplies ? FontWeight.w600 : FontWeight.w400),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
            ]),
          ]),
        ),
      ),
    );
  }
}
