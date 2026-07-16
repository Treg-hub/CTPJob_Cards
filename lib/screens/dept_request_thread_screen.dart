import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../models/dept_request.dart';
import '../services/dept_request_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/fleet_photo_viewer.dart';

/// Two-way thread + auto-ack on open for target-dept managers.
class DeptRequestThreadScreen extends StatefulWidget {
  final String requestId;

  const DeptRequestThreadScreen({super.key, required this.requestId});

  @override
  State<DeptRequestThreadScreen> createState() => _DeptRequestThreadScreenState();
}

class _DeptRequestThreadScreenState extends State<DeptRequestThreadScreen> {
  final _svc = DeptRequestService.instance;
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<String> _pendingPhotos = [];

  bool _sending = false;
  bool _ackAttempted = false;
  bool _acting = false;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance
          .collection(Collections.deptRequests)
          .doc(widget.requestId);

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  EmployeeLike? get _me {
    final e = writeAttributionEmployee ?? realEmployee ?? currentEmployee;
    if (e == null) return null;
    return EmployeeLike(e.clockNo, e.name, e.department, e);
  }

  bool _isTargetManager(DeptRequest item) {
    final me = realEmployee ?? currentEmployee;
    if (me == null) return false;
    if (role_utils.isAdmin(me)) return true;
    final isMgr = role_utils.roleFromEmployee(me) == role_utils.UserRole.manager;
    return isMgr && me.department == item.targetDepartment;
  }

  bool _isCreator(DeptRequest item) {
    final clock = realEmployee?.clockNo ?? currentEmployee?.clockNo;
    return clock != null && clock == item.createdByClockNo;
  }

  Future<void> _maybeAutoAck(DeptRequest item) async {
    if (_ackAttempted) return;
    if (item.status != DeptRequestStatus.open) return;
    if (!_isTargetManager(item)) return;
    // Creator opening their own request (same-dept self-reminder) still auto-acks
    // when they are target manager — that's intentional for same-dept use.
    final me = _me;
    if (me == null) return;
    _ackAttempted = true;
    try {
      await _svc.acknowledge(
        requestId: widget.requestId,
        clockNo: me.clockNo,
        name: me.name,
      );
    } catch (_) {
      _ackAttempted = false;
    }
  }

  Future<void> _addPhoto() async {
    if (_pendingPhotos.length >= DeptRequestService.maxPhotosPerMessage) return;
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
    final path = await _svc.pickAndCompressPhoto(source);
    if (path == null || !mounted) return;
    setState(() => _pendingPhotos.add(path));
  }

  Future<void> _sendComment() async {
    if (!guardPersonaSubmit(context)) return;
    final text = _composer.text.trim();
    if (text.isEmpty && _pendingPhotos.isEmpty) return;
    final me = _me;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      await _svc.addComment(
        requestId: widget.requestId,
        text: text,
        byClockNo: me.clockNo,
        byName: me.name,
        localPhotoPaths: List<String>.from(_pendingPhotos),
      );
      _composer.clear();
      setState(() => _pendingPhotos.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send reply: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markDone(DeptRequest item) async {
    if (!guardPersonaSubmit(context)) return;
    final me = _me;
    if (me == null) return;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark done'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'What was done?',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Done')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _acting = true);
    try {
      await _svc.markDone(
        requestId: widget.requestId,
        clockNo: me.clockNo,
        name: me.name,
        doneNote: noteCtrl.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark done: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      noteCtrl.dispose();
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _withdraw(DeptRequest item) async {
    if (!guardPersonaSubmit(context)) return;
    final me = _me;
    if (me == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw request?'),
        content: const Text('This closes the request without action from the other side.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _acting = true);
    try {
      await _svc.withdraw(requestId: widget.requestId, clockNo: me.clockNo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not withdraw: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CtpAppBar(title: 'Dept Request'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text('This request was removed.'));
          }
          final item = DeptRequest.fromDoc(snap.data!);
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoAck(item));

          final canPost = item.status != DeptRequestStatus.withdrawn &&
              (_isTargetManager(item) ||
                  _isCreator(item) ||
                  role_utils.isAdmin(realEmployee ?? currentEmployee));
          final canDone = item.isActive && _isTargetManager(item);
          final canWithdraw =
              item.status == DeptRequestStatus.open && _isCreator(item);

          return Column(
            children: [
              Expanded(child: _thread(item)),
              if (canDone || canWithdraw)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      if (canWithdraw)
                        OutlinedButton(
                          onPressed: _acting ? null : () => _withdraw(item),
                          child: const Text('Withdraw'),
                        ),
                      const Spacer(),
                      if (canDone)
                        FilledButton(
                          onPressed: _acting ? null : () => _markDone(item),
                          style: FilledButton.styleFrom(backgroundColor: kBrandOrange),
                          child: const Text('Mark done'),
                        ),
                    ],
                  ),
                ),
              if (canPost) _composerBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _thread(DeptRequest item) {
    final colors = Theme.of(context).appColors;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _ref
          .collection(Collections.deptRequestComments)
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        final comments =
            (snap.data?.docs ?? []).map(DeptRequestComment.fromDoc).toList();
        return ListView(
          controller: _scroll,
          padding: ScreenInsets.listPadding(context, horizontal: 12, top: 8),
          children: [
            _headerCard(item, colors),
            if (comments.isEmpty && snap.connectionState != ConnectionState.waiting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No replies yet.',
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

  Widget _headerCard(DeptRequest item, AppColors colors) {
    final fmt = DateFormat('dd MMM yyyy HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.requestNumber.isEmpty ? 'Dept Request' : item.requestNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                _statusChip(item.status, colors),
                if (item.isOpenOver48h) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: const Text('Open > 48h', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.amber.withValues(alpha: 0.25),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.locationPath,
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
            Text(
              '${item.fromDepartment} → ${item.targetDepartment}',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            Text(
              'By ${item.createdByName}'
              '${item.createdAt != null ? ' · ${fmt.format(item.createdAt!)}' : ''}',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Text(
              item.message.isEmpty ? '(photo)' : item.message,
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
            if (item.photoUrls.isNotEmpty) _photoStrip(item.photoUrls),
            if (item.doneNote != null && item.doneNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Done note: ${item.doneNote}',
                  style: TextStyle(fontSize: 13, color: colors.wasteGreen)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(DeptRequestStatus s, AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: deptRequestStatusColor(context, s).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: deptRequestStatusColor(context, s),
        ),
      ),
    );
  }

  Widget _photoStrip(List<String> urls, {double size = 72}) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: size,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => FleetPhotoThumb(
            urls: urls,
            index: i,
            size: size,
          ),
        ),
      ),
    );
  }

  Widget _commentBubble(
      DeptRequestComment c, DeptRequest item, AppColors colors) {
    final mine = c.byClockNo == (realEmployee?.clockNo ?? currentEmployee?.clockNo);
    final fmt = DateFormat('dd MMM HH:mm');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: mine
              ? kBrandOrange.withValues(alpha: 0.12)
              : colors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.cardSurface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.byName}${c.createdAt != null ? ' · ${fmt.format(c.createdAt!)}' : ''}',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            if (c.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(c.text, style: const TextStyle(height: 1.3)),
            ],
            if (c.photoUrls.isNotEmpty) _photoStrip(c.photoUrls, size: 56),
          ],
        ),
      ),
    );
  }

  Widget _composerBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingPhotos.isNotEmpty)
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingPhotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(_pendingPhotos[i]),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _pendingPhotos.removeAt(i)),
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: _pendingPhotos.length >=
                          DeptRequestService.maxPhotosPerMessage
                      ? null
                      : _addPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Reply…',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: _sending ? null : _sendComment,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  style: IconButton.styleFrom(backgroundColor: kBrandOrange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight holder so we don't import Employee model only for clock/name.
class EmployeeLike {
  final String clockNo;
  final String name;
  final String department;
  final Object raw;
  EmployeeLike(this.clockNo, this.name, this.department, this.raw);
}
