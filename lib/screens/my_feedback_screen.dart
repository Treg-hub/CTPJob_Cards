import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../constants/collections.dart';
import '../main.dart' show realEmployee;
import '../models/feedback_item.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/fleet_photo_viewer.dart';
import '../utils/persona_audit.dart';
import 'feedback_thread_screen.dart';
import '../utils/screen_insets.dart';

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
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ComposeFeedbackDialog(
        onSubmitted: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thank you! Your feedback has been submitted.'),
              backgroundColor: Colors.green,
            ),
          );
        },
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
                  padding: ScreenInsets.listPadding(
                    context,
                    horizontal: 12,
                    top: 8,
                    clearFab: true,
                  ),
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
    final hasPhotos = item.photoUrls.isNotEmpty;
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
              item.feedback.isEmpty
                  ? (hasPhotos ? '(photo)' : '(empty)')
                  : item.feedback,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
            if (hasPhotos) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: item.photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => FleetPhotoThumb(
                    urls: item.photoUrls,
                    index: i,
                    size: 56,
                  ),
                ),
              ),
            ],
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
              if (hasPhotos) ...[
                const SizedBox(width: 10),
                Icon(Icons.photo_outlined, size: 14, color: colors.textMuted),
                const SizedBox(width: 2),
                Text('${item.photoUrls.length}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted)),
              ],
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Stateful compose dialog so pending photo paths survive rebuilds.
class _ComposeFeedbackDialog extends StatefulWidget {
  const _ComposeFeedbackDialog({required this.onSubmitted});

  final VoidCallback onSubmitted;

  @override
  State<_ComposeFeedbackDialog> createState() => _ComposeFeedbackDialogState();
}

class _ComposeFeedbackDialogState extends State<_ComposeFeedbackDialog> {
  final _controller = TextEditingController();
  final _photos = <String>[];
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= FeedbackService.maxPhotosPerMessage) return;
    if (!guardPersonaSubmit(context)) return;
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add photo'),
        content: const Text('Camera or gallery?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Gallery'),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    final path = await FeedbackService.instance.pickAndCompressPhoto(source);
    if (path == null || !mounted) return;
    setState(() => _photos.add(path));
  }

  Future<void> _submit() async {
    final feedback = _controller.text.trim();
    if (feedback.isEmpty && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some text or a photo')),
      );
      return;
    }
    if (!guardPersonaSubmit(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    final session = writeAttributionEmployee ?? realEmployee;
    setState(() => _submitting = true);
    try {
      final col = FirebaseFirestore.instance.collection(Collections.feedback);
      final docRef = col.doc();
      List<String> photoUrls = const [];
      if (_photos.isNotEmpty) {
        photoUrls = await FeedbackService.instance.uploadPhotos(
          feedbackId: docRef.id,
          localPaths: List<String>.from(_photos),
        );
      }
      await docRef.set({
        'feedback': feedback,
        'userName': session?.name ?? 'Unknown',
        'clockNo': session?.clockNo ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
        if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
        ...personaAuditFields(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error submitting feedback: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final canAddMore = _photos.length < FeedbackService.maxPhotosPerMessage;
    return AlertDialog(
      title: const Text('Send Feedback'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('What improvements would you like to see?'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              autofocus: true,
              enabled: !_submitting,
              decoration: const InputDecoration(
                hintText: 'Type your feedback here...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_photos.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_photos[i]),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (!_submitting)
                          Positioned(
                            top: -6,
                            right: -6,
                            child: Material(
                              color: Colors.black87,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => setState(() => _photos.removeAt(i)),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            if (_photos.isNotEmpty) const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (!_submitting && canAddMore) ? _addPhoto : null,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(
                canAddMore
                    ? 'Add photo (${_photos.length}/${FeedbackService.maxPhotosPerMessage})'
                    : 'Photo limit reached',
              ),
              style: OutlinedButton.styleFrom(foregroundColor: colors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: kBrandOrange, foregroundColor: Colors.white),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
