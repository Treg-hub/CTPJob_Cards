import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_issue_widgets.dart';
import 'fleet_log_work_screen.dart';

/// Detailed view of a single fleet issue.
/// - Reporters: read-only
/// - Mechanic: acknowledge + resolve actions
/// - Cost manager: read-only + link to work record
/// - Admin/manager: all actions including cancel
class FleetIssueDetailScreen extends ConsumerStatefulWidget {
  final String issueId;
  const FleetIssueDetailScreen({super.key, required this.issueId});

  @override
  ConsumerState<FleetIssueDetailScreen> createState() =>
      _FleetIssueDetailScreenState();
}

class _FleetIssueDetailScreenState
    extends ConsumerState<FleetIssueDetailScreen> {
  final _service = FleetService();
  bool _actionInProgress = false;

  Future<void> _acknowledge(FleetIssue issue) async {
    final emp = currentEmployee;
    if (emp == null) return;
    setState(() => _actionInProgress = true);
    try {
      await _service.acknowledgeIssue(issue.id!, emp.clockNo, emp.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Issue acknowledged.'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _resolveWithNote(FleetIssue issue) async {
    final emp = currentEmployee;
    if (emp == null) return;

    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve with Note'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter resolution note (required)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resolve')),
        ],
      ),
    );

    noteCtrl.dispose();
    if (confirmed != true) return;
    final note = noteCtrl.text.trim();
    if (note.isEmpty) return;

    setState(() => _actionInProgress = true);
    try {
      await _service.resolveIssueWithNote(
          issue.id!, note, emp.clockNo, emp.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Issue resolved.'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _logWorkAndResolve(FleetIssue issue) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FleetLogWorkScreen(
        preSelectedAssetId: issue.assetId,
        preSelectedAssetName: issue.assetName,
        linkedIssueId: issue.id,
      ),
    ));
  }

  Future<void> _cancel(FleetIssue issue) async {
    final emp = currentEmployee;
    if (emp == null) return;

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to cancel this issue?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                  hintText: 'Reason (optional)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Cancel Issue', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    reasonCtrl.dispose();
    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      await _service.cancelIssue(issue.id!, emp.clockNo, emp.name,
          reason: reasonCtrl.text.trim().isEmpty
              ? null
              : reasonCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = currentEmployee;
    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;

    final isMechanic = role_utils.isFleetMechanic(emp, settings);
    final isCostMgr = role_utils.isFleetCostManager(emp, settings);
    final isAdmin = role_utils.isFleetAdmin(emp);
    final canCancel = isMechanic || isCostMgr || isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Detail'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<FleetIssue?>(
        stream: _service
            .watchIssues(limit: 1)
            .map((list) =>
                list.where((i) => i.id == widget.issueId).firstOrNull),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final issue = snapshot.data;
          if (issue == null) {
            // Fetch once as fallback
            return FutureBuilder<FleetIssue?>(
              future: _service.getIssue(widget.issueId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.data == null) {
                  return const Center(child: Text('Issue not found.'));
                }
                return _IssueBody(
                  issue: snap.data!,
                  isMechanic: isMechanic,
                  isCostMgr: isCostMgr,
                  canCancel: canCancel,
                  actionInProgress: _actionInProgress,
                  onAcknowledge: () => _acknowledge(snap.data!),
                  onResolveWithNote: () => _resolveWithNote(snap.data!),
                  onLogWork: () => _logWorkAndResolve(snap.data!),
                  onCancel: () => _cancel(snap.data!),
                );
              },
            );
          }
          return _IssueBody(
            issue: issue,
            isMechanic: isMechanic,
            isCostMgr: isCostMgr,
            canCancel: canCancel,
            actionInProgress: _actionInProgress,
            onAcknowledge: () => _acknowledge(issue),
            onResolveWithNote: () => _resolveWithNote(issue),
            onLogWork: () => _logWorkAndResolve(issue),
            onCancel: () => _cancel(issue),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Issue body — stateless, driven by issue data
// ---------------------------------------------------------------------------

class _IssueBody extends StatelessWidget {
  const _IssueBody({
    required this.issue,
    required this.isMechanic,
    required this.isCostMgr,
    required this.canCancel,
    required this.actionInProgress,
    required this.onAcknowledge,
    required this.onResolveWithNote,
    required this.onLogWork,
    required this.onCancel,
  });

  final FleetIssue issue;
  final bool isMechanic;
  final bool isCostMgr;
  final bool canCancel;
  final bool actionInProgress;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolveWithNote;
  final VoidCallback onLogWork;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy HH:mm');
    final colors = Theme.of(context).extension<AppColors>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Text(issue.assetName,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            FleetSeverityBadge(severity: issue.severity),
            const SizedBox(width: 8),
            FleetStatusBadge(status: issue.status),
            const SizedBox(width: 8),
            Chip(
              label: Text(issue.shift.displayLabel,
                  style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Description ──────────────────────────────────────────────────
        _DetailRow(
          label: 'Description',
          child: Text(issue.description),
        ),
        const Divider(),

        // ── Meta ─────────────────────────────────────────────────────────
        _DetailRow(
          label: 'Reported by',
          child: Text('${issue.reportedByName} (${issue.reportedByClockNo})'),
        ),
        _DetailRow(
          label: 'Reported at',
          child: Text(issue.createdAt != null ? fmt.format(issue.createdAt!) : '—'),
        ),
        if (issue.acknowledgedByClockNo != null) ...[
          _DetailRow(
            label: 'Acknowledged by',
            child: Text(issue.acknowledgedByClockNo!),
          ),
          _DetailRow(
            label: 'Acknowledged at',
            child: Text(issue.acknowledgedAt != null
                ? fmt.format(issue.acknowledgedAt!)
                : '—'),
          ),
        ],
        if (issue.status == FleetIssueStatus.resolved) ...[
          const Divider(),
          _DetailRow(
            label: 'Resolved by',
            child: Text(issue.resolvedByClockNo ?? '—'),
          ),
          _DetailRow(
            label: 'Resolved at',
            child: Text(issue.resolvedAt != null
                ? fmt.format(issue.resolvedAt!)
                : '—'),
          ),
          if (issue.resolutionType == FleetIssueResolutionType.note &&
              issue.resolutionNote != null)
            _DetailRow(
              label: 'Resolution note',
              child: Text(issue.resolutionNote!),
            ),
          if (issue.linkedWorkRecordId != null)
            _DetailRow(
              label: 'Work record',
              child: Text(issue.linkedWorkRecordId!,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.blue)),
            ),
        ],
        const Divider(),

        // ── Photos ────────────────────────────────────────────────────────
        if (issue.photos.isNotEmpty) ...[
          Text('Photos',
              style: TextStyle(
                  color: colors?.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: issue.photos
                .map((url) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(url,
                          width: 100, height: 100, fit: BoxFit.cover),
                    ))
                .toList(),
          ),
          const Divider(),
        ],

        // ── Mechanic actions ──────────────────────────────────────────────
        if (isMechanic && issue.status.isOpen) ...[
          const SizedBox(height: 8),
          if (issue.status == FleetIssueStatus.open)
            _ActionButton(
              label: 'Acknowledge',
              icon: Icons.thumb_up_outlined,
              color: Colors.blue,
              loading: actionInProgress,
              onPressed: onAcknowledge,
            ),
          if (issue.status == FleetIssueStatus.acknowledged) ...[
            _ActionButton(
              label: 'Log Work & Resolve',
              icon: Icons.build,
              color: kBrandOrange,
              loading: actionInProgress,
              onPressed: onLogWork,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'Resolve with Note',
              icon: Icons.check_circle_outline,
              color: Colors.green,
              loading: actionInProgress,
              onPressed: onResolveWithNote,
            ),
          ],
          const SizedBox(height: 8),
        ],

        // ── Cancel (admin/manager/mechanic) ───────────────────────────────
        if (canCancel && issue.status.isOpen) ...[
          OutlinedButton.icon(
            onPressed: actionInProgress ? null : onCancel,
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            label: const Text('Cancel Issue',
                style: TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: colors?.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 12)),
      ),
    );
  }
}
