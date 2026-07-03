import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:intl/intl.dart';

import '../constants/collections.dart';
import '../models/feedback_item.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'feedback_thread_screen.dart';

/// Admin-only feedback triage board.
///
/// Streams the shared `feedback` collection (written from MyFeedbackScreen's
/// "Give Feedback" dialog) and lets an admin track each item through a simple
/// workflow — New → Planned → Implemented → Declined — and attach private
/// implementation notes. Public replies to the submitter go through the
/// two-way thread (FeedbackThreadScreen → feedback_comments subcollection);
/// status changes and replies notify the submitter via Cloud Functions.
/// This is an internal tracking tool: the entry point lives in the admin
/// Settings tab and the screen is gated again on `isAdmin` here so it can
/// never be opened by a non-admin who deep-links in.

class FeedbackAdminScreen extends StatefulWidget {
  const FeedbackAdminScreen({super.key});

  @override
  State<FeedbackAdminScreen> createState() => _FeedbackAdminScreenState();
}

class _FeedbackAdminScreenState extends State<FeedbackAdminScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  /// null until the admin check resolves; gates the whole screen.
  bool? _isAdmin;
  String? _currentClockNo;

  /// null = show all statuses; otherwise only the matching status.
  FeedbackStatus? _filter;

  @override
  void initState() {
    super.initState();
    _resolveAdmin();
  }

  Future<void> _resolveAdmin() async {
    final clockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    bool isAdmin = false;
    if (clockNo != null) {
      final emp = await _firestoreService.getEmployee(clockNo);
      isAdmin = emp?.isAdmin ?? false;
    }
    if (!mounted) return;
    setState(() {
      _currentClockNo = clockNo;
      _isAdmin = isAdmin;
    });
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  Future<void> _setStatus(String docId, FeedbackStatus status) async {
    if (!guardPersonaSubmit(context)) return;
    try {
      await FirebaseFirestore.instance.collection(Collections.feedback).doc(docId).set({
        'status': status.id,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedByClockNo': _currentClockNo,
      }, SetOptions(merge: true));
    } catch (e) {
      _showError('Could not update status: $e');
    }
  }

  Future<void> _editNotes(String docId, String existing) async {
    if (!guardPersonaSubmit(context)) return;
    final controller = TextEditingController(text: existing);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Implementation notes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'What did you do, plan to do, or why declined…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    try {
      await FirebaseFirestore.instance.collection(Collections.feedback).doc(docId).set({
        'adminNotes': result,
        'adminNotesUpdatedAt': FieldValue.serverTimestamp(),
        'adminNotesByClockNo': _currentClockNo,
      }, SetOptions(merge: true));
    } catch (e) {
      _showError('Could not save notes: $e');
    }
  }

  Future<void> _deleteFeedback(String docId) async {
    if (!guardPersonaSubmit(context)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete feedback'),
        content: const Text('Permanently remove this feedback item? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance.collection(Collections.feedback).doc(docId).delete();
    } catch (e) {
      _showError('Could not delete: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  // ── Colours ─────────────────────────────────────────────────────────────

  Color _statusColor(FeedbackStatus s) => feedbackStatusColor(context, s);

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Feedback'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isAdmin == null
          ? const Center(child: CircularProgressIndicator())
          : _isAdmin == false
              ? _accessDenied()
              : _buildBoard(),
    );
  }

  Widget _accessDenied() {
    final colors = Theme.of(context).appColors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, size: 48, color: colors.textMuted),
        const SizedBox(height: 12),
        Text('Admin access required', style: TextStyle(color: colors.textMuted)),
      ]),
    );
  }

  Widget _buildBoard() {
    final colors = Theme.of(context).appColors;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(Collections.feedback)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading feedback: ${snap.error}', textAlign: TextAlign.center),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = (snap.data?.docs ?? []).map(FeedbackItem.fromDoc).toList();

        // Per-status counts power the filter chip badges (computed once).
        final counts = <FeedbackStatus, int>{for (final s in FeedbackStatus.values) s: 0};
        for (final it in items) {
          counts[it.status] = (counts[it.status] ?? 0) + 1;
        }

        final visible = _filter == null ? items : items.where((it) => it.status == _filter).toList();

        return Column(children: [
          _filterBar(total: items.length, counts: counts),
          Expanded(
            child: items.isEmpty
                ? _emptyState('No feedback submitted yet', Icons.inbox_outlined)
                : visible.isEmpty
                    ? _emptyState('No ${_filter!.label.toLowerCase()} feedback', Icons.filter_alt_off_outlined)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _feedbackCard(visible[i], colors),
                      ),
          ),
        ]);
      },
    );
  }

  Widget _emptyState(String message, IconData icon) {
    final colors = Theme.of(context).appColors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: colors.textMuted),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: colors.textMuted)),
      ]),
    );
  }

  Widget _filterBar({required int total, required Map<FeedbackStatus, int> counts}) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _filterChip(label: 'All', count: total, value: null),
          for (final s in FeedbackStatus.values)
            _filterChip(label: s.label, count: counts[s] ?? 0, value: s, color: _statusColor(s)),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required int count, FeedbackStatus? value, Color? color}) {
    final selected = _filter == value;
    final chipColor = color ?? kBrandOrange;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label · $count', style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: chipColor,
        labelStyle: TextStyle(
          color: selected ? onColor(chipColor) : Theme.of(context).appColors.chipUnselectedLabel,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }

  Widget _feedbackCard(FeedbackItem item, AppColors colors) {
    final fmt = DateFormat('d MMM yyyy HH:mm');
    final statusColor = _statusColor(item.status);
    final hasNotes = item.notes.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.cardSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header: submitter + submitted time + overflow menu.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(Icons.person_outline, size: 16, color: statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.userName.isEmpty ? 'Unknown' : item.userName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  '${item.clockNo.isEmpty ? '—' : 'Clock ${item.clockNo}'}'
                  '${item.submittedAt != null ? '  •  ${fmt.format(item.submittedAt!)}' : ''}',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: colors.textMuted),
              onSelected: (v) {
                if (v == 'delete') _deleteFeedback(item.id);
                if (v == 'notes') _editNotes(item.id, item.notes);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'notes', child: Text('Edit notes')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          const SizedBox(height: 8),

          // The feedback itself.
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(item.feedback.isEmpty ? '(empty)' : item.feedback, style: const TextStyle(fontSize: 14, height: 1.3)),
          ),
          const SizedBox(height: 12),

          // Status selector.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: FeedbackStatus.values.map((s) {
              final selected = item.status == s;
              final c = _statusColor(s);
              return ChoiceChip(
                label: Text(s.label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                // Skip the write when re-tapping the already-active status.
                onSelected: (_) => selected ? null : _setStatus(item.id, s),
                selectedColor: c,
                labelStyle: TextStyle(
                  color: selected ? onColor(c) : colors.chipUnselectedLabel,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Public two-way thread with the submitter (feedback_comments).
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FeedbackThreadScreen(feedbackId: item.id)),
              ),
              icon: Icon(
                item.commentCount > 0 ? Icons.forum : Icons.reply,
                size: 16,
                color: item.commentCount > 0 ? kBrandOrange : null,
              ),
              label: Text(item.commentCount > 0
                  ? 'Thread (${item.commentCount})'
                  : 'Reply to submitter'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor:
                    item.commentCount > 0 ? kBrandOrange : colors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Admin notes block (PRIVATE — never shown in the public thread).
          if (hasNotes)
            InkWell(
              onTap: () => _editNotes(item.id, item.notes),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.inputFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.sticky_note_2_outlined, size: 14, color: colors.textMuted),
                    const SizedBox(width: 6),
                    Text('NOTES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: colors.textMuted)),
                    const Spacer(),
                    Icon(Icons.edit_outlined, size: 14, color: colors.textMuted),
                  ]),
                  const SizedBox(height: 6),
                  Text(item.notes, style: const TextStyle(fontSize: 13, height: 1.3)),
                  if (item.notesUpdatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text('Updated ${fmt.format(item.notesUpdatedAt!)}', style: TextStyle(fontSize: 10, color: colors.textMuted)),
                  ],
                ]),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _editNotes(item.id, ''),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add note'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: colors.textMuted,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

