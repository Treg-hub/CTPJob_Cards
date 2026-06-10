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
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_photo_viewer.dart';
import 'fleet_asset_detail_screen.dart';
import 'fleet_log_work_screen.dart';

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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _startJob(FleetIssue issue) async {
    final emp = currentEmployee;
    if (emp == null || issue.status != FleetIssueStatus.open) return;
    setState(() => _actionInProgress = true);
    try {
      await _service.acknowledgeIssue(issue.id!, emp.clockNo, emp.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Job started. Come back and tap "Finish the fix" when done.',
            ),
            backgroundColor: Colors.green,
          ),
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

  Future<void> _finishFix(FleetIssue issue) async {
    final emp = currentEmployee;
    if (emp == null || issue.status != FleetIssueStatus.acknowledged) return;
    setState(() => _actionInProgress = true);
    try {
      if (!mounted) return;
      final fixed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FleetLogWorkScreen(
            preSelectedAssetId: issue.assetId,
            preSelectedAssetName: issue.assetName,
            linkedIssueId: issue.id,
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
    final isCostMgr = role_utils.isFleetCostManager(emp, settings);
    final isAdmin = role_utils.isFleetAdmin(emp);
    final isReporter = role_utils.isFleetReporter(emp, settings);
    final canCancel = isMechanic || isCostMgr || isAdmin;

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
            onStartJob: () => _startJob(issue),
            onFinishFix: () => _finishFix(issue),
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
    required this.onStartJob,
    required this.onFinishFix,
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
  final VoidCallback onStartJob;
  final VoidCallback onFinishFix;
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
        _RepeatOffenderHint(
          assetId: issue.assetId,
          assetName: issue.assetName,
        ),
        if (mechanicView && issue.status.isOpen) ...[
          const SizedBox(height: 16),
          if (issue.status == FleetIssueStatus.open) ...[
            _ActionButton(
              label: 'Start job',
              icon: Icons.play_circle_outline,
              color: Colors.blue,
              loading: actionInProgress,
              onPressed: onStartJob,
            ),
            const SizedBox(height: 8),
            Text(
              'Use this when the repair will take time (e.g. transmission). '
              'The job clock starts now — finish and log the work when complete.',
              style: TextStyle(fontSize: 12, color: colors?.textMuted),
            ),
          ] else ...[
            if (issue.acknowledgedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Job started ${fmt.format(issue.acknowledgedAt!)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors?.textMuted,
                  ),
                ),
              ),
            _ActionButton(
              label: 'Finish the fix',
              icon: Icons.build_circle_outlined,
              color: kBrandOrange,
              loading: actionInProgress,
              onPressed: onFinishFix,
            ),
            const SizedBox(height: 8),
            Text(
              'Record the hour-meter reading and what you did to close this problem.',
              style: TextStyle(fontSize: 12, color: colors?.textMuted),
            ),
          ],
          const SizedBox(height: 12),
          if (issue.severity == FleetIssueSeverity.outOfService)
            // OOS faults must be closed with a work log (decided 2026-06-10).
            Center(
              child: Text(
                'Out of service — must be closed by logging the repair.',
                style: TextStyle(fontSize: 12, color: colors?.textMuted),
              ),
            )
          else
            Center(
              child: TextButton(
                onPressed: actionInProgress ? null : onResolveWithNote,
                child: const Text('Close with a note only (no work log)'),
              ),
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
        if (!mechanicView && issue.acknowledgedByClockNo != null) ...[
          _DetailRow(
            label: 'Acknowledged by',
            child: Text(issue.acknowledgedByLabel ?? '—'),
          ),
          _DetailRow(
            label: 'Acknowledged at',
            child: Text(issue.acknowledgedAt != null
                ? fmt.format(issue.acknowledgedAt!)
                : '—'),
          ),
        ],
        if (mechanicView && issue.acknowledgedAt != null) ...[
          _DetailRow(
            label: 'Started fixing',
            child: Text(fmt.format(issue.acknowledgedAt!)),
          ),
        ],
        if (issue.status == FleetIssueStatus.resolved) ...[
          const Divider(),
          if (mechanicView) ...[
            _DetailRow(
              label: 'Fixed at',
              child: Text(issue.resolvedAt != null
                  ? fmt.format(issue.resolvedAt!)
                  : '—'),
            ),
            if (issue.resolutionType == FleetIssueResolutionType.note &&
                issue.resolutionNote != null)
              _DetailRow(
                label: 'Note',
                child: Text(issue.resolutionNote!),
              ),
          ] else ...[
            _DetailRow(
              label: 'Resolved by',
              child: Text(issue.resolvedByLabel ?? '—'),
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
        ],
        if (issue.status == FleetIssueStatus.cancelled) ...[
          const Divider(),
          _DetailRow(
            label: 'Cancelled by',
            child: Text(issue.cancelledByLabel ?? '—'),
          ),
          _DetailRow(
            label: 'Cancelled at',
            child: Text(issue.cancelledAt != null
                ? fmt.format(issue.cancelledAt!)
                : '—'),
          ),
          if (issue.cancelReason != null)
            _DetailRow(
              label: 'Reason',
              child: Text(issue.cancelReason!),
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
            runSpacing: 8,
            children: [
              for (var i = 0; i < issue.photos.length; i++)
                FleetPhotoThumb(urls: issue.photos, index: i),
            ],
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

/// Surfaces chronic machines: when this asset has had 2+ non-cancelled
/// problems in the last 30 days, show a tappable hint into its history.
class _RepeatOffenderHint extends StatelessWidget {
  const _RepeatOffenderHint({
    required this.assetId,
    required this.assetName,
  });

  final String assetId;
  final String assetName;

  static String _ordinal(int n) {
    if (n == 2) return '2nd';
    if (n == 3) return '3rd';
    return '${n}th';
  }

  @override
  Widget build(BuildContext context) {
    if (assetId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<int>(
      future: FleetService().watchAssetIssues(assetId).first.then((issues) {
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        return issues
            .where((i) =>
                i.status != FleetIssueStatus.cancelled &&
                (i.createdAt?.isAfter(cutoff) ?? false))
            .length;
      }),
      builder: (context, snapshot) {
        final count = snapshot.data;
        if (count == null || count < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FleetAssetDetailScreen(assetId: assetId),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                border: Border.all(color: Colors.amber.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_ordinal(count)} problem on $assetName in 30 days — '
                      'tap to view history.',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
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
