import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../constants/collections.dart';
import '../models/feedback_item.dart';
import '../models/system_review_note.dart';
import '../services/feedback_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/fleet_photo_viewer.dart';
import 'feedback_thread_screen.dart';

/// Admin-only board with two tracks:
/// 1. **Staff feedback** — triage the closed loop (status + private notes + thread).
/// 2. **Walk notes** — isAdmin park-for-later notes while walking the floor
///    (`system_review_notes`). No staff loop / no CFs; consolidate later by
///    module + status.
///
/// Entry: Home Quick Actions **Feedback** tile (admins). Gated on dual isAdmin.
class FeedbackAdminScreen extends StatefulWidget {
  const FeedbackAdminScreen({super.key});

  @override
  State<FeedbackAdminScreen> createState() => _FeedbackAdminScreenState();
}

class _FeedbackAdminScreenState extends State<FeedbackAdminScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late final TabController _tabs;

  /// null until the admin check resolves; gates the whole screen.
  bool? _isAdmin;
  String? _currentClockNo;
  String? _currentName;

  /// Staff feedback status filter (null = all).
  FeedbackStatus? _feedbackFilter;

  /// Walk notes status filter (null = all).
  SystemReviewNoteStatus? _noteFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _resolveAdmin();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _resolveAdmin() async {
    final clockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    bool isAdmin = false;
    String? name;
    if (clockNo != null) {
      final emp = await _firestoreService.getEmployee(clockNo);
      isAdmin = role_utils.isAdmin(emp);
      name = emp?.name;
    }
    if (!mounted) return;
    setState(() {
      _currentClockNo = clockNo;
      _currentName = name;
      _isAdmin = isAdmin;
    });
  }

  // ── Staff feedback writes ────────────────────────────────────────────────

  Future<void> _setFeedbackStatus(String docId, FeedbackStatus status) async {
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

  Future<void> _editFeedbackNotes(String docId, String existing) async {
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
    if (result == null) return;
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

  // ── Walk notes writes ────────────────────────────────────────────────────

  Future<void> _parkNote() async {
    if (!guardPersonaSubmit(context)) return;
    final result = await showDialog<_ParkNoteDraft>(
      context: context,
      builder: (ctx) => const _ParkNoteDialog(),
    );
    if (result == null || !mounted) return;
    if (result.heading.isEmpty && result.text.isEmpty && result.localPhotoPaths.isEmpty) {
      _showError('Add a heading, text, or a photo');
      return;
    }

    try {
      final col = FirebaseFirestore.instance.collection(Collections.systemReviewNotes);
      final ref = col.doc();
      List<String> photoUrls = const [];
      if (result.localPhotoPaths.isNotEmpty) {
        photoUrls = await FeedbackService.instance.uploadSystemReviewNotePhotos(
          noteId: ref.id,
          localPaths: result.localPhotoPaths,
        );
      }
      await ref.set({
        'heading': result.heading,
        'text': result.text,
        'module': result.module,
        'area': result.area,
        'status': SystemReviewNoteStatus.open.id,
        'photoUrls': photoUrls,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdByClockNo': _currentClockNo ?? '',
        'createdByName': _currentName ?? '',
        'reviewNotes': '',
        ...personaAuditFields(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Walk note parked')),
      );
      // Prefer Walk notes tab after save.
      if (_tabs.index != 1) _tabs.animateTo(1);
    } catch (e) {
      _showError('Could not park note: $e');
    }
  }

  Future<void> _setNoteStatus(String docId, SystemReviewNoteStatus status) async {
    if (!guardPersonaSubmit(context)) return;
    try {
      await FirebaseFirestore.instance
          .collection(Collections.systemReviewNotes)
          .doc(docId)
          .set({
        'status': status.id,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedByClockNo': _currentClockNo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _showError('Could not update status: $e');
    }
  }

  /// Append dated detail to the same note (keeps prior observations).
  Future<void> _appendNoteDetail(SystemReviewNote item) async {
    if (!guardPersonaSubmit(context)) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add more detail'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Appends a dated block under the existing note. Prior text is kept.',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).appColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What else did you find?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
            child: const Text('Append'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      _showError('Add some detail to append');
      return;
    }
    final stamp = DateFormat('d MMM yyyy HH:mm').format(DateTime.now());
    final who = (_currentName ?? '').trim().isNotEmpty
        ? _currentName!.trim()
        : (_currentClockNo ?? 'admin');
    final block = '---\n[$stamp · $who]\n$result';
    final nextText = item.text.trim().isEmpty ? result : '${item.text.trim()}\n\n$block';
    try {
      await FirebaseFirestore.instance
          .collection(Collections.systemReviewNotes)
          .doc(item.id)
          .set({
        'text': nextText,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastAppendedAt': FieldValue.serverTimestamp(),
        'lastAppendedByClockNo': _currentClockNo,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detail added to note')),
      );
    } catch (e) {
      _showError('Could not append: $e');
    }
  }

  /// Edit heading / body / module / area on the same note (full replace of those fields).
  Future<void> _editNoteContent(SystemReviewNote item) async {
    if (!guardPersonaSubmit(context)) return;
    final result = await showDialog<_ParkNoteDraft>(
      context: context,
      builder: (ctx) => _ParkNoteDialog(
        initialHeading: item.heading,
        initialText: item.text,
        initialModule: item.module.isEmpty ? null : item.module,
        initialArea: item.area,
        editMode: true,
      ),
    );
    if (result == null) return;
    if (result.heading.isEmpty && result.text.isEmpty && item.photoUrls.isEmpty) {
      _showError('Keep a heading or body text');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(Collections.systemReviewNotes)
          .doc(item.id)
          .set({
        'heading': result.heading,
        'text': result.text,
        'module': result.module,
        'area': result.area,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note updated')),
      );
    } catch (e) {
      _showError('Could not update note: $e');
    }
  }

  Future<void> _editReviewNotes(String docId, String existing) async {
    if (!guardPersonaSubmit(context)) return;
    final controller = TextEditingController(text: existing);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Review notes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'How this fits the system, next step, or why dropped…',
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
    if (result == null) return;
    try {
      await FirebaseFirestore.instance
          .collection(Collections.systemReviewNotes)
          .doc(docId)
          .set({
        'reviewNotes': result,
        'reviewNotesUpdatedAt': FieldValue.serverTimestamp(),
        'reviewNotesByClockNo': _currentClockNo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _showError('Could not save review notes: $e');
    }
  }

  Future<void> _deleteNote(String docId) async {
    if (!guardPersonaSubmit(context)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete walk note'),
        content: const Text('Permanently remove this parked note? This cannot be undone.'),
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
      await FirebaseFirestore.instance
          .collection(Collections.systemReviewNotes)
          .doc(docId)
          .delete();
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

  Color _statusColor(FeedbackStatus s) => feedbackStatusColor(context, s);
  Color _noteStatusColor(SystemReviewNoteStatus s) =>
      systemReviewNoteStatusColor(context, s);

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showFab = _isAdmin == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback & notes'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        bottom: _isAdmin == true
            ? TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Staff feedback'),
                  Tab(text: 'Walk notes'),
                ],
              )
            : null,
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _parkNote,
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_note),
              label: Text(_tabs.index == 1 ? 'Park note' : 'Walk note'),
            )
          : null,
      body: _isAdmin == null
          ? const Center(child: CircularProgressIndicator())
          : _isAdmin == false
              ? _accessDenied()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildFeedbackBoard(),
                    _buildWalkNotesBoard(),
                  ],
                ),
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

  Widget _emptyState(String message, IconData icon) {
    final colors = Theme.of(context).appColors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: colors.textMuted),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: colors.textMuted), textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Staff feedback board ─────────────────────────────────────────────────

  Widget _buildFeedbackBoard() {
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
        final counts = <FeedbackStatus, int>{for (final s in FeedbackStatus.values) s: 0};
        for (final it in items) {
          counts[it.status] = (counts[it.status] ?? 0) + 1;
        }
        final visible =
            _feedbackFilter == null ? items : items.where((it) => it.status == _feedbackFilter).toList();

        return Column(children: [
          _feedbackFilterBar(total: items.length, counts: counts),
          Expanded(
            child: items.isEmpty
                ? _emptyState('No staff feedback yet', Icons.inbox_outlined)
                : visible.isEmpty
                    ? _emptyState(
                        'No ${_feedbackFilter!.label.toLowerCase()} feedback',
                        Icons.filter_alt_off_outlined,
                      )
                    : ListView.builder(
                        padding: ScreenInsets.listPadding(
                          context,
                          horizontal: 12,
                          top: 4,
                          clearFab: true,
                          extendedFab: true,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _feedbackCard(visible[i], colors),
                      ),
          ),
        ]);
      },
    );
  }

  Widget _feedbackFilterBar({required int total, required Map<FeedbackStatus, int> counts}) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _feedbackFilterChip(label: 'All', count: total, value: null),
          for (final s in FeedbackStatus.values)
            _feedbackFilterChip(
              label: s.label,
              count: counts[s] ?? 0,
              value: s,
              color: _statusColor(s),
            ),
        ],
      ),
    );
  }

  Widget _feedbackFilterChip({
    required String label,
    required int count,
    FeedbackStatus? value,
    Color? color,
  }) {
    final selected = _feedbackFilter == value;
    final chipColor = color ?? kBrandOrange;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label · $count', style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _feedbackFilter = value),
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
                if (v == 'notes') _editFeedbackNotes(item.id, item.notes);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'notes', child: Text('Edit notes')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              item.feedback.isEmpty
                  ? (item.photoUrls.isNotEmpty ? '(photo)' : '(empty)')
                  : item.feedback,
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
          ),
          if (item.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => FleetPhotoThumb(
                  urls: item.photoUrls,
                  index: i,
                  size: 64,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: FeedbackStatus.values.map((s) {
              final selected = item.status == s;
              final c = _statusColor(s);
              return ChoiceChip(
                label: Text(s.label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => selected ? null : _setFeedbackStatus(item.id, s),
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
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FeedbackThreadScreen(feedbackId: item.id)),
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
                foregroundColor: item.commentCount > 0 ? kBrandOrange : colors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (hasNotes)
            InkWell(
              onTap: () => _editFeedbackNotes(item.id, item.notes),
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
                    Text(
                      'NOTES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: colors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.edit_outlined, size: 14, color: colors.textMuted),
                  ]),
                  const SizedBox(height: 6),
                  Text(item.notes, style: const TextStyle(fontSize: 13, height: 1.3)),
                  if (item.notesUpdatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Updated ${fmt.format(item.notesUpdatedAt!)}',
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  ],
                ]),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _editFeedbackNotes(item.id, ''),
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

  // ── Walk notes board ─────────────────────────────────────────────────────

  Widget _buildWalkNotesBoard() {
    final colors = Theme.of(context).appColors;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(Collections.systemReviewNotes)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading walk notes: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = (snap.data?.docs ?? []).map(SystemReviewNote.fromDoc).toList();
        final counts = <SystemReviewNoteStatus, int>{
          for (final s in SystemReviewNoteStatus.values) s: 0,
        };
        for (final it in items) {
          counts[it.status] = (counts[it.status] ?? 0) + 1;
        }
        final visible =
            _noteFilter == null ? items : items.where((it) => it.status == _noteFilter).toList();

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              'Park ideas while you walk (with a heading). Open a note later to Add more detail — prior text is kept. Use Review notes for fit-to-system thinking.',
              style: TextStyle(fontSize: 12, color: colors.textMuted, height: 1.3),
            ),
          ),
          _noteFilterBar(total: items.length, counts: counts),
          Expanded(
            child: items.isEmpty
                ? _emptyState(
                    'No walk notes yet.\nTap Park note to capture one.',
                    Icons.edit_note_outlined,
                  )
                : visible.isEmpty
                    ? _emptyState(
                        'No ${_noteFilter!.label.toLowerCase()} notes',
                        Icons.filter_alt_off_outlined,
                      )
                    : ListView.builder(
                        padding: ScreenInsets.listPadding(
                          context,
                          horizontal: 12,
                          top: 4,
                          clearFab: true,
                          extendedFab: true,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _noteCard(visible[i], colors),
                      ),
          ),
        ]);
      },
    );
  }

  Widget _noteFilterBar({
    required int total,
    required Map<SystemReviewNoteStatus, int> counts,
  }) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _noteFilterChip(label: 'All', count: total, value: null),
          for (final s in SystemReviewNoteStatus.values)
            _noteFilterChip(
              label: s.label,
              count: counts[s] ?? 0,
              value: s,
              color: _noteStatusColor(s),
            ),
        ],
      ),
    );
  }

  Widget _noteFilterChip({
    required String label,
    required int count,
    SystemReviewNoteStatus? value,
    Color? color,
  }) {
    final selected = _noteFilter == value;
    final chipColor = color ?? kBrandOrange;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label · $count', style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _noteFilter = value),
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

  Widget _noteCard(SystemReviewNote item, AppColors colors) {
    final fmt = DateFormat('d MMM yyyy HH:mm');
    final statusColor = _noteStatusColor(item.status);
    final hasReview = item.reviewNotes.trim().isNotEmpty;
    final metaBits = <String>[
      if (item.module.isNotEmpty) item.module,
      if (item.area.isNotEmpty) item.area,
      if (item.createdByName.isNotEmpty) item.createdByName,
      if (item.createdAt != null) fmt.format(item.createdAt!),
      if (item.updatedAt != null &&
          (item.createdAt == null ||
              item.updatedAt!.difference(item.createdAt!).inMinutes.abs() >= 1))
        'updated ${fmt.format(item.updatedAt!)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.cardSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_note, size: 16, color: statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.displayTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (metaBits.isNotEmpty)
                  Text(
                    metaBits.join('  •  '),
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: colors.textMuted),
              onSelected: (v) {
                if (v == 'append') _appendNoteDetail(item);
                if (v == 'edit') _editNoteContent(item);
                if (v == 'review') _editReviewNotes(item.id, item.reviewNotes);
                if (v == 'delete') _deleteNote(item.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'append', child: Text('Add more detail')),
                PopupMenuItem(value: 'edit', child: Text('Edit heading & body')),
                PopupMenuItem(value: 'review', child: Text('Edit review notes')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              item.text.isEmpty
                  ? (item.photoUrls.isNotEmpty ? '(photo)' : '(empty)')
                  : item.text,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
          if (item.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => FleetPhotoThumb(
                  urls: item.photoUrls,
                  index: i,
                  size: 64,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Primary actions for cumulative notes.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => _appendNoteDetail(item),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add more detail'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: kBrandOrange,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _editNoteContent(item),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: SystemReviewNoteStatus.values.map((s) {
              final selected = item.status == s;
              final c = _noteStatusColor(s);
              return ChoiceChip(
                label: Text(s.label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => selected ? null : _setNoteStatus(item.id, s),
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
          if (hasReview)
            InkWell(
              onTap: () => _editReviewNotes(item.id, item.reviewNotes),
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
                    Text(
                      'REVIEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: colors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.edit_outlined, size: 14, color: colors.textMuted),
                  ]),
                  const SizedBox(height: 6),
                  Text(item.reviewNotes, style: const TextStyle(fontSize: 13, height: 1.3)),
                  if (item.reviewNotesUpdatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Updated ${fmt.format(item.reviewNotesUpdatedAt!)}',
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  ],
                ]),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _editReviewNotes(item.id, ''),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add review notes'),
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

// ── Park / edit note dialog ──────────────────────────────────────────────────

class _ParkNoteDraft {
  final String heading;
  final String text;
  final String module;
  final String area;
  final List<String> localPhotoPaths;

  const _ParkNoteDraft({
    required this.heading,
    required this.text,
    required this.module,
    required this.area,
    required this.localPhotoPaths,
  });
}

class _ParkNoteDialog extends StatefulWidget {
  const _ParkNoteDialog({
    this.initialHeading = '',
    this.initialText = '',
    this.initialModule,
    this.initialArea = '',
    this.editMode = false,
  });

  final String initialHeading;
  final String initialText;
  final String? initialModule;
  final String initialArea;
  final bool editMode;

  @override
  State<_ParkNoteDialog> createState() => _ParkNoteDialogState();
}

class _ParkNoteDialogState extends State<_ParkNoteDialog> {
  late final TextEditingController _heading;
  late final TextEditingController _text;
  late final TextEditingController _area;
  String? _module;
  final List<String> _photos = [];

  @override
  void initState() {
    super.initState();
    _heading = TextEditingController(text: widget.initialHeading);
    _text = TextEditingController(text: widget.initialText);
    _area = TextEditingController(text: widget.initialArea);
    _module = widget.initialModule;
  }

  @override
  void dispose() {
    _heading.dispose();
    _text.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_photos.length >= FeedbackService.maxPhotosPerMessage) return;
    final path = await FeedbackService.instance.pickAndCompressPhoto(source);
    if (path == null || !mounted) return;
    setState(() => _photos.add(path));
  }

  void _submit() {
    final heading = _heading.text.trim();
    final text = _text.text.trim();
    if (!widget.editMode && heading.isEmpty && text.isEmpty && _photos.isEmpty) return;
    Navigator.pop(
      context,
      _ParkNoteDraft(
        heading: heading,
        text: text,
        module: _module ?? '',
        area: _area.text.trim(),
        localPhotoPaths: List<String>.from(_photos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return AlertDialog(
      title: Text(widget.editMode ? 'Edit walk note' : 'Park a walk note'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editMode
                    ? 'Change heading, body, module, or area. To keep history, prefer Add more detail on the card.'
                    : 'Give it a short heading so you can find it later. You can keep adding detail to the same note.',
                style: TextStyle(fontSize: 12, color: colors.textMuted, height: 1.3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _heading,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Heading',
                  hintText: 'e.g. Ink tank colour cards hard to read',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                maxLines: 5,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: widget.editMode ? 'Body (full text)' : 'What did you notice?',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('Module (optional)', style: TextStyle(fontSize: 12, color: colors.textMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: kSystemReviewModules.map((m) {
                  final selected = _module == m;
                  return ChoiceChip(
                    label: Text(m, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => setState(() => _module = selected ? null : m),
                    selectedColor: kBrandOrange,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : colors.chipUnselectedLabel,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _area,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Area / location (optional)',
                  hintText: 'e.g. Press 3, main gate, ink tanks',
                  border: OutlineInputBorder(),
                ),
              ),
              if (!widget.editMode) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _photos.length >= FeedbackService.maxPhotosPerMessage
                          ? null
                          : () => _addPhoto(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Photo'),
                    ),
                    TextButton.icon(
                      onPressed: _photos.length >= FeedbackService.maxPhotosPerMessage
                          ? null
                          : () => _addPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                    ),
                    if (_photos.isNotEmpty)
                      Text(
                        '${_photos.length}/${FeedbackService.maxPhotosPerMessage}',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: kBrandOrange,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.editMode ? 'Save' : 'Park note'),
        ),
      ],
    );
  }
}
