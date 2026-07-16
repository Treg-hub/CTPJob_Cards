import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../services/dept_request_service.dart';
import '../theme/app_theme.dart';
import '../utils/persona_audit.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/dept_request_tip.dart';

/// Compose a manager Dept Request: Department → Area breadcrumb + note + photos.
class CreateDeptRequestScreen extends ConsumerStatefulWidget {
  const CreateDeptRequestScreen({super.key});

  @override
  ConsumerState<CreateDeptRequestScreen> createState() =>
      _CreateDeptRequestScreenState();
}

class _CreateDeptRequestScreenState
    extends ConsumerState<CreateDeptRequestScreen> {
  final _messageCtrl = TextEditingController();
  final _svc = DeptRequestService.instance;

  String? _department;
  String? _area;
  final List<String> _photos = [];
  bool _submitting = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final me = realEmployee ?? currentEmployee;
    if (me == null) return false;
    if (!role_utils.isAdmin(me) &&
        role_utils.roleFromEmployee(me) != role_utils.UserRole.manager) {
      return false;
    }
    return _department != null &&
        _area != null &&
        (_messageCtrl.text.trim().isNotEmpty || _photos.isNotEmpty) &&
        !_submitting;
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= DeptRequestService.maxPhotosPerMessage) return;
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
    setState(() => _photos.add(path));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!guardPersonaSubmit(context)) return;
    final me = writeAttributionEmployee ?? realEmployee ?? currentEmployee;
    if (me == null) return;

    setState(() => _submitting = true);
    try {
      final result = await _svc.create(
        targetDepartment: _department!,
        area: _area!,
        message: _messageCtrl.text.trim(),
        createdByName: me.name,
        localPhotoPaths: List<String>.from(_photos),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.requestNumber.isEmpty
                ? 'Dept Request sent'
                : '${result.requestNumber} sent',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Scaffold(
      appBar: const CtpAppBar(title: 'New Dept Request'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(Collections.structures)
            .doc('factory')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error loading structure: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final raw = snap.data!.data() ?? {};
          final data = (raw['data'] as Map<String, dynamic>?) ?? {};
          final areas = _department != null
              ? (data[_department] as Map<String, dynamic>? ?? {}).keys.toList()
              : <String>[];

          return ListView(
            padding: ScreenInsets.listPadding(context),
            children: [
              DeptRequestTip(
                dismissible: true,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.cardSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBrandOrange.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'For manager notes: please do X, something needs attention, '
                    'or a reminder for yourself / your peers. '
                    'Pick department and area. Not for machine breakdowns — use Create Job Card.',
                    style: TextStyle(fontSize: 13, color: colors.textMuted, height: 1.35),
                  ),
                ),
              ),
              if (_department != null || _area != null) ...[
                Container(
                  padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: colors.cardSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selection — ${_department ?? ''}${_area != null ? ' > $_area' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _department = null;
                          _area = null;
                        }),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_department == null) ...[
                const Text('Department',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: data.keys.map((dept) {
                    final d = dept.toString();
                    return ChoiceChip(
                      label: Text(d),
                      selected: _department == d,
                      onSelected: (_) => setState(() {
                        _department = d;
                        _area = null;
                      }),
                      labelStyle: _department == d
                          ? const TextStyle(color: Color(0xFFFF8C42))
                          : TextStyle(color: colors.chipUnselectedLabel),
                    );
                  }).toList(),
                ),
              ],
              if (_department != null && _area == null) ...[
                const SizedBox(height: 8),
                const Text('Area / Section',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: areas.map((area) {
                    final a = area.toString();
                    return ChoiceChip(
                      label: Text(a),
                      selected: _area == a,
                      onSelected: (_) => setState(() => _area = a),
                      labelStyle: _area == a
                          ? const TextStyle(color: Color(0xFFFF8C42))
                          : TextStyle(color: colors.chipUnselectedLabel),
                    );
                  }).toList(),
                ),
              ],
              if (_area != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'What needs attention or what should they do?',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Photos (optional, max ${DeptRequestService.maxPhotosPerMessage})',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _photos.length >= DeptRequestService.maxPhotosPerMessage
                          ? null
                          : _addPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (_photos.isNotEmpty)
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => Stack(
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
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Colors.white),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(24, 24),
                              ),
                              onPressed: () => setState(() => _photos.removeAt(i)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'Sending…' : 'Send Dept Request'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
