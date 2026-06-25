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
import '../widgets/fleet_app_bar.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import 'fleet_mark_fixed_screen.dart';
import 'fleet_work_record_detail_screen.dart';

/// Detailed view of a single fleet issue.
/// - Reporters: read-only
/// - Mechanic: acknowledge + resolve actions
/// - Cost manager: read-only + link to work record
/// - Admin/manager: all actions including cancel
class FleetIssueDetailScreen extends ConsumerStatefulWidget {
  final String issueId;
  final bool mechanicMode;
  const FleetIssueDetailScreen({
    super.key,
    required this.issueId,
    this.mechanicMode = false,
  });

  @override
  ConsumerState<FleetIssueDetailScreen> createState() =>
      _FleetIssueDetailScreenState();
}

class _FleetIssueDetailScreenState
    extends ConsumerState<FleetIssueDetailScreen> {
  final _service = FleetService();
  bool _actionInProgress = false;
  bool _hasAutoAcknowledged = false;

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Silently acknowledges the issue when the mechanic opens the screen —
  // no separate "Start job" tap required.
  Future<void> _autoAcknowledge(FleetIssue issue) async {
    if (_hasAutoAcknowledged) return;
    final emp = currentEmployee;
    if (emp == null || issue.status != FleetIssueStatus.open) return;
    _hasAutoAcknowledged = true;
    try {
      await _service.acknowledgeIssue(issue.id!, emp.clockNo, emp.name);
    } catch (e) {
      debugPrint('Auto-acknowledge error: $e');
    }
  }

  Future<void> _finishFix(FleetIssue issue) async {
    final emp = currentEmployee;
    if (emp == null || !issue.status.isOpen) return;
    setState(() => _actionInProgress = true);
    try {
      if (!mounted) return;
      final fixed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FleetMarkFixedScreen(
            preSelectedAssetId: issue.assetId,
            preSelectedAssetName: issue.assetName,
            linkedIssueId: issue.id!,
          ),
        ),
      );
      if (fixed == true && mounted) {
        Navigator.of(context).pop();
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

    // Out-of-service issues must be closed with a work record — a note alone
    // can't close a safety-critical fault (decided 2026-06-10).
    if (issue.severity == FleetIssueSeverity.outOfService) {
      _showError(
        'Out-of-service problems must be closed by logging the repair '
        '(use "Finish the fix").',
      );
      return;
    }

    final noteCtrl = TextEditingController();
    final mechanicClose = widget.mechanicMode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          mechanicClose ? 'Close without a work log' : 'Resolve with Note',
        ),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: mechanicClose
                ? 'Brief note (e.g. duplicate report, not a fault)'
                : 'Enter resolution note (required)',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(mechanicClose ? 'Close problem' : 'Resolve')),
        ],
      ),
    );

    if (confirmed != true) {
      noteCtrl.dispose();
      return;
    }
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (note.isEmpty) return;

    setState(() => _actionInProgress = true);
    try {
      await _service.resolveIssueWithNote(
          issue.id!, note, emp.clockNo, emp.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.mechanicMode ? 'Problem closed.' : 'Issue resolved.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.mechanicMode) {
          Navigator.of(context).pop();
        }
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

    if (confirmed != true) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    setState(() => _actionInProgress = true);
    try {
      await _service.cancelIssue(issue.id!, emp.clockNo, emp.name,
          reason: reason.isEmpty ? null : reason);
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
    final isAdmin = role_utils.isFleetAdmin(emp);
    final isReporter = role_utils.isFleetReporter(emp, settings);
    final canCancel = isMechanic || isAdmin;

    final mechanicView = widget.mechanicMode || isMechanic;

    return Scaffold(
      appBar: FleetAppBar(
        title: mechanicView ? 'Problem' : 'Issue Detail',
      ),
      body: StreamBuilder<FleetIssue?>(
        stream: _service.watchIssue(widget.issueId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final issue = snapshot.data;
          if (issue == null) {
            return const Center(child: Text('Issue not found.'));
          }

          // Auto-acknowledge when mechanic first opens an open issue.
          if (mechanicView && issue.status == FleetIssueStatus.open) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _autoAcknowledge(issue),
            );
          }

          final isOwnReport =
              emp != null && issue.reportedByClockNo == emp.clockNo;
          return _IssueBody(
            issue: issue,
            isMechanic: isMechanic,
            mechanicView: mechanicView,
            isReporter: isReporter,
            isOwnReport: isOwnReport,
            canCancel: canCancel,
            actionInProgress: _actionInProgress,
            onMarkAsFixed: () => _finishFix(issue),
            onResolveWithNote: () => _resolveWithNote(issue),
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
    required this.mechanicView,
    required this.isReporter,
    required this.isOwnReport,
    required this.canCancel,
    required this.actionInProgress,
    required this.onMarkAsFixed,
    required this.onResolveWithNote,
    required this.onCancel,
  });

  final FleetIssue issue;
  final bool isMechanic;
  final bool mechanicView;
  final bool isReporter;
  final bool isOwnReport;
  final bool canCancel;
  final bool actionInProgress;
  final VoidCallback onMarkAsFixed;
  final VoidCallback onResolveWithNote;
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
            if (mechanicView)
              FleetMechanicStatusBadge(status: issue.status)
            else
              FleetStatusBadge(status: issue.status),
            if (isOwnReport) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('Your report'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                backgroundColor: kBrandOrange.withValues(alpha: 0.15),
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        if (mechanicView && issue.status.isOpen) ...[
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Mark as Fixed',
            icon: Icons.build_circle_outlined,
            color: kBrandOrange,
            loading: actionInProgress,
            onPressed: onMarkAsFixed,
          ),
          const SizedBox(height: 8),
          Text(
            'Record what you did, the meter reading, and close this problem.',
            style: TextStyle(fontSize: 12, color: colors?.textMuted),
          ),
          const Divider(height: 32),
        ],
        if (isReporter && !isMechanic) ...[
          const SizedBox(height: 12),
          Text(
            isOwnReport
                ? 'Your report is visible to the maintenance team and other reporters.'
                : 'Reported by ${issue.reportedByName} — visible to all reporters for transparency.',
            style: TextStyle(fontSize: 12, color: colors?.textMuted),
          ),
        ],
        const SizedBox(height: 16),

        // ── Report ───────────────────────────────────────────────────────
        Text(
          'Report',
          style: TextStyle(
            color: colors?.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _DetailRow(
          label: 'Reported at',
          child: Text(
              issue.createdAt != null ? fmt.format(issue.createdAt!) : '—'),
        ),
        _DetailRow(
          label: 'Reported by',
          child: Text(
            mechanicView
                ? issue.reportedByName
                : '${issue.reportedByName} (${issue.reportedByClockNo})',
          ),
        ),
        const SizedBox(height: 8),
        _DetailRow(
          label: 'Description',
          child: Text(issue.description),
        ),
        if (issue.parts.isNotEmpty)
          _DetailRow(
            label: 'Parts affected',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: issue.parts
                  .map((p) => Chip(
                        label: Text(p, style: const TextStyle(fontSize: 12)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ),
        const Divider(),

        // ── Progress timeline ────────────────────────────────────────────
        Text(
          'Progress',
          style: TextStyle(
            color: colors?.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        FleetIssueTimeline(issue: issue),
        if (issue.status == FleetIssueStatus.resolved &&
            issue.resolutionType == FleetIssueResolutionType.note &&
            issue.resolutionNote != null) ...[
          const SizedBox(height: 8),
          _DetailRow(
            label: mechanicView ? 'Note' : 'Resolution note',
            child: Text(issue.resolutionNote!),
          ),
        ],

        // ── The fix — what the mechanic actually did ─────────────────────
        if (issue.resolutionType == FleetIssueResolutionType.workRecord &&
            issue.linkedWorkRecordId != null) ...[
          const SizedBox(height: 16),
          Text(
            'The fix',
            style: TextStyle(
              color: colors?.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _FixSummaryCard(
            workRecordId: issue.linkedWorkRecordId!,
            mechanicView: mechanicView,
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

        // ── Cancel (admin/manager; hidden in simplified mechanic view) ───
        if (canCancel && issue.status.isOpen && !mechanicView) ...[
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

/// Summary of the work record that fixed this issue — the mechanic's own
/// description of the fix, kept visually distinct from the fault report.
class _FixSummaryCard extends StatelessWidget {
  const _FixSummaryCard({
    required this.workRecordId,
    required this.mechanicView,
  });

  final String workRecordId;
  final bool mechanicView;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final service = FleetService();
    final fmt = DateFormat('d MMM yyyy');

    return FutureBuilder<FleetWorkRecord?>(
      future: service.getWorkRecord(workRecordId),
      builder: (context, snapshot) {
        final record = snapshot.data;
        if (record == null) {
          return Text(
            snapshot.connectionState == ConnectionState.waiting
                ? 'Loading the fix…'
                : 'Work record not available.',
            style: TextStyle(color: colors?.textMuted, fontSize: 13),
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          color: Colors.green.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FleetWorkRecordDetailScreen(
                  workRecordId: workRecordId,
                  mechanicMode: mechanicView,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.build_circle_outlined,
                          size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          record.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    record.description,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                  StreamBuilder<List<FleetWorkPart>>(
                    stream: service.watchParts(workRecordId),
                    builder: (context, partsSnap) {
                      final parts = partsSnap.data ?? [];
                      if (parts.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: parts
                              .map((p) => Chip(
                                    label: Text(
                                      p.quantity != null
                                          ? '${p.partName} ×${p.quantity}'
                                          : p.partName,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fixed by ${record.loggedByName} · '
                    '${fmt.format(record.endDate)}',
                    style: TextStyle(fontSize: 11, color: colors?.textMuted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
