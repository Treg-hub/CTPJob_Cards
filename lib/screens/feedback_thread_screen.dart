import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/collections.dart';
import '../main.dart' show realEmployee;
import '../models/feedback_item.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ctp_app_bar.dart';
import '../utils/persona_audit.dart';
import '../utils/screen_insets.dart';

/// Public two-way thread on a single feedback item.
///
/// Opened from My Feedback (worker), the admin triage board, or a parked
/// inbox notification. Shows the original submission + status, then the
/// `feedback_comments` subcollection as a conversation. Only the original
/// submitter and admins can post (also enforced server-side in
/// firestore.rules); anyone else who lands here gets a read-only view.
/// Private `adminNotes` are deliberately NOT shown here.
class FeedbackThreadScreen extends StatefulWidget {
  final String feedbackId;

  const FeedbackThreadScreen({super.key, required this.feedbackId});

  @override
  State<FeedbackThreadScreen> createState() => _FeedbackThreadScreenState();
}

class _FeedbackThreadScreenState extends State<FeedbackThreadScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _viewerIsAdmin = false;
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _feedbackRef =>
      FirebaseFirestore.instance.collection(Collections.feedback).doc(widget.feedbackId);

  @override
  void initState() {
    super.initState();
    _resolveViewer();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _resolveViewer() async {
    final clockNo = realEmployee?.clockNo;
    if (clockNo == null) return;
    final emp = await _firestoreService.getEmployee(clockNo);
    if (!mounted) return;
    setState(() => _viewerIsAdmin = emp?.isAdmin ?? false);
  }

  Future<void> _sendComment() async {
    if (!guardPersonaSubmit(context)) return;
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final me = writeAttributionEmployee ?? realEmployee;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      await _feedbackRef.collection(Collections.feedbackComments).add({
        'text': text,
        'byClockNo': me.clockNo,
        'byName': me.name,
        'byIsAdmin': _viewerIsAdmin,
        'createdAt': FieldValue.serverTimestamp(),
        ...personaAuditFields(),
      });
      _composer.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send reply: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CtpAppBar(title: 'Feedback'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _feedbackRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error loading feedback: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text('This feedback item was removed.'));
          }
          final item = FeedbackItem.fromDoc(snap.data!);
          final viewerClockNo = realEmployee?.clockNo;
          final canPost = _viewerIsAdmin || (viewerClockNo != null && viewerClockNo == item.clockNo);
          return Column(children: [
            Expanded(child: _thread(item)),
            if (canPost) _composerBar(),
          ]);
        },
      ),
    );
  }

  Widget _thread(FeedbackItem item) {
    final colors = Theme.of(context).appColors;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _feedbackRef
          .collection(Collections.feedbackComments)
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        final comments = (snap.data?.docs ?? []).map(FeedbackComment.fromDoc).toList();
        return ListView(
          controller: _scroll,
          padding: ScreenInsets.listPadding(context, horizontal: 12, top: 8),
          children: [
            _originalCard(item, colors),
            if (comments.isEmpty && snap.connectionState != ConnectionState.waiting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _viewerIsAdmin ? 'No replies yet — post the first update.' : 'No replies yet.',
                    style: TextStyle(color: colors.textMuted, fontSize: 13),
                  ),
                ),
              ),
            ...comments.map((c) => _commentBubble(c, item, colors)),
          ],
        );
      },
    );
  }

  Widget _originalCard(FeedbackItem item, AppColors colors) {
    final fmt = DateFormat('d MMM yyyy HH:mm');
    final statusColor = feedbackStatusColor(context, item.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colors.cardSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                item.userName.isEmpty ? 'Unknown' : item.userName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _viewerIsAdmin ? item.status.label : item.status.workerLabel,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
              ),
            ),
          ]),
          if (item.submittedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(fmt.format(item.submittedAt!),
                  style: TextStyle(fontSize: 11, color: colors.textMuted)),
            ),
          const SizedBox(height: 8),
          Text(item.feedback.isEmpty ? '(empty)' : item.feedback,
              style: const TextStyle(fontSize: 14, height: 1.3)),
        ]),
      ),
    );
  }

  Widget _commentBubble(FeedbackComment c, FeedbackItem item, AppColors colors) {
    final fmt = DateFormat('d MMM HH:mm');
    final mine = c.byClockNo == realEmployee?.clockNo;
    final accent = c.byIsAdmin ? kBrandOrange : colors.statusOpen;
    final author = c.byIsAdmin
        ? 'CTP Team${c.byName.isNotEmpty ? ' — ${c.byName}' : ''}'
        : (c.byName.isNotEmpty ? c.byName : 'Clock ${c.byClockNo}');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: c.byIsAdmin ? accent.withValues(alpha: 0.10) : colors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: c.byIsAdmin ? 0.45 : 0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(c.byIsAdmin ? Icons.verified_user_outlined : Icons.person_outline,
                size: 13, color: accent),
            const SizedBox(width: 4),
            Text(author,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
            if (c.createdAt != null) ...[
              const SizedBox(width: 8),
              Text(fmt.format(c.createdAt!),
                  style: TextStyle(fontSize: 10, color: colors.textMuted)),
            ],
          ]),
          const SizedBox(height: 4),
          Text(c.text, style: const TextStyle(fontSize: 13.5, height: 1.3)),
        ]),
      ),
    );
  }

  Widget _composerBar() {
    final colors = Theme.of(context).appColors;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        color: colors.cardSurface,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _viewerIsAdmin ? 'Reply to this feedback…' : 'Add a comment…',
                isDense: true,
                filled: true,
                fillColor: colors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _sending ? null : _sendComment,
            icon: _sending
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            color: kBrandOrange,
          ),
        ]),
      ),
    );
  }
}
