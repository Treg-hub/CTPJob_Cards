import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_cost_line.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_work_comment.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_photo_viewer.dart';
import 'fleet_add_cost_screen.dart';
import 'fleet_issue_detail_screen.dart';
import 'fleet_log_work_screen.dart';

/// Detail view of a single work record.
/// - Mechanic: sees all fields except cost amounts; can edit if no cost lines.
/// - Cost manager/admin: sees full detail including costs; can add cost lines.
class FleetWorkRecordDetailScreen extends ConsumerStatefulWidget {
  final String workRecordId;
  final bool mechanicMode;
  const FleetWorkRecordDetailScreen({
    super.key,
    required this.workRecordId,
    this.mechanicMode = false,
  });

  @override
  ConsumerState<FleetWorkRecordDetailScreen> createState() =>
      _FleetWorkRecordDetailScreenState();
}

class _FleetWorkRecordDetailScreenState
    extends ConsumerState<FleetWorkRecordDetailScreen> {
  final _service = FleetService();

  Future<void> _markNoCost(FleetWorkRecord record) async {
    final emp = currentEmployee;
    if (emp == null || record.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No cost needed?'),
        content: const Text(
          'This marks the job as needing no spend (e.g. an adjustment or '
          'inspection). It will leave the costing queue and the mechanic '
          'can no longer edit it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('No cost needed'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.markWorkRecordNoCost(record.id!, emp.clockNo, emp.name);
      if (mounted) {
        setState(() {}); // re-fetch the record
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job marked as no cost needed.'),
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
    final canSeeCosts = isCostMgr || isAdmin;
    final canComment = isMechanic || isAdmin || isCostMgr;

    final mechanicView = widget.mechanicMode || (isMechanic && !canSeeCosts);

    return Scaffold(
      appBar: FleetAppBar(title: mechanicView ? 'Job Details' : 'Work Record'),
      // Stream so offline-synced photos, edits, and the costed flag update
      // live — a FutureBuilder here showed stale data next to live sub-streams.
      body: StreamBuilder<FleetWorkRecord?>(
        stream: _service.watchWorkRecord(widget.workRecordId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final record = snapshot.data;
          if (record == null) {
            return const Center(child: Text('Work record not found.'));
          }
          return _RecordBody(
            record: record,
            isMechanic: isMechanic,
            isAdmin: isAdmin,
            mechanicView: mechanicView,
            canSeeCosts: canSeeCosts,
            canComment: canComment,
            service: _service,
            onMarkNoCost: () => _markNoCost(record),
            onEdit: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FleetLogWorkScreen(
                workRecordId: record.id,
              ),
            )),
            onAddCost: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FleetAddCostScreen(
                preSelectedAssetId: record.assetId,
                preSelectedAssetName: record.assetName,
                preSelectedWorkRecordId: record.id,
                preSelectedWorkNumber: record.workNumber,
              ),
            )),
          );
        },
      ),
    );
  }
}

class _RecordBody extends ConsumerWidget {
  const _RecordBody({
    required this.record,
    required this.isMechanic,
    required this.isAdmin,
    required this.mechanicView,
    required this.canSeeCosts,
    required this.canComment,
    required this.service,
    required this.onEdit,
    required this.onAddCost,
    required this.onMarkNoCost,
  });

  final FleetWorkRecord record;
  final bool isMechanic;
  final bool isAdmin;
  final bool mechanicView;
  final bool canSeeCosts;
  final bool canComment;
  final FleetService service;
  final VoidCallback onEdit;
  final VoidCallback onAddCost;
  final VoidCallback onMarkNoCost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('d MMM yyyy');
    final colors = Theme.of(context).extension<AppColors>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Work number + title ──────────────────────────────────────────
        if (!mechanicView)
          Text(record.workNumber,
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: colors?.textMuted,
                  fontSize: 12)),
        if (!mechanicView) const SizedBox(height: 4),
        Text(record.title,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        // ── Type + asset ─────────────────────────────────────────────────
        Wrap(
          spacing: 8,
          children: [
            Chip(
              label: Text(record.workTypeName,
                  style: const TextStyle(fontSize: 12)),
              backgroundColor: kBrandOrange.withAlpha(30),
              padding: EdgeInsets.zero,
            ),
            Chip(
              label: Text(record.assetName,
                  style: const TextStyle(fontSize: 12)),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const Divider(),

        // ── Details ──────────────────────────────────────────────────────
        _Row(
          label: mechanicView ? 'What you did' : 'Description',
          child: Text(record.description),
        ),
        if (!mechanicView || record.labourHours > 0)
          _Row(
            label: 'Labour Hours',
            child: Text('${record.labourHours} h'),
          ),
        if (record.machineHoursReading != null)
          _Row(
            label: mechanicView ? 'Hour meter reading' : 'Machine Hours Reading',
            child: Text('${record.machineHoursReading} h'),
          ),
        if (mechanicView) ...[
          _Row(
            label: 'Started',
            child: Text(dateFmt.format(record.startDate)),
          ),
          _Row(
            label: 'Finished',
            child: Text(dateFmt.format(record.endDate)),
          ),
        ] else
          _Row(
            label: 'Date Range',
            child: Text(
                '${dateFmt.format(record.startDate)} → ${dateFmt.format(record.endDate)}'),
          ),
        _Row(
          label: 'Logged by',
          child: Text(
            mechanicView
                ? record.loggedByName
                : '${record.loggedByName} (${record.loggedByClockNo})',
          ),
        ),
        const Divider(),

        // ── Parts ────────────────────────────────────────────────────────
        const Text('Parts Used',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        StreamBuilder<List<FleetWorkPart>>(
          stream: service.watchParts(record.id!),
          builder: (context, snapshot) {
            final parts = snapshot.data ?? [];
            if (parts.isEmpty) {
              return Text('None recorded.',
                  style: TextStyle(color: colors?.textMuted));
            }
            return Column(
              children: parts
                  .map((p) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.partName),
                        trailing: p.quantity != null
                            ? Text('×${p.quantity}')
                            : null,
                      ))
                  .toList(),
            );
          },
        ),

        // ── Photos ───────────────────────────────────────────────────────
        if (record.photos.isNotEmpty) ...[
          const Divider(),
          const Text('Photos',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < record.photos.length; i++)
                FleetPhotoThumb(urls: record.photos, index: i),
            ],
          ),
        ],

        // ── Linked issues ────────────────────────────────────────────────
        if (record.linkedIssueIds.isNotEmpty) ...[
          const Divider(),
          Text(
            mechanicView ? 'Problem fixed' : 'Linked Issues',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _LinkedIssueList(
            issueIds: record.linkedIssueIds,
            service: service,
            mechanicView: mechanicView,
          ),
        ],

        const Divider(),

        // ── Costs section (cost manager/admin only) ───────────────────────
        if (canSeeCosts) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cost Lines',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Row(
                children: [
                  if (record.costStatus == FleetCostStatus.pending)
                    TextButton(
                      onPressed: onMarkNoCost,
                      child: const Text('No cost needed',
                          style: TextStyle(fontSize: 12)),
                    ),
                  TextButton.icon(
                    icon:
                        const Icon(Icons.add, size: 18, color: kBrandOrange),
                    label: const Text('Add Cost',
                        style: TextStyle(color: kBrandOrange)),
                    onPressed: onAddCost,
                  ),
                ],
              ),
            ],
          ),
          if (record.costStatus == FleetCostStatus.noCost)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Marked as no cost needed.',
                style: TextStyle(color: colors?.textMuted, fontSize: 12),
              ),
            ),
          StreamBuilder<List<FleetCostLine>>(
            stream: service.watchCostLines(assetId: record.assetId),
            builder: (context, snapshot) {
              final allLines = snapshot.data ?? [];
              final lines = allLines
                  .where((l) => l.workRecordId == record.id)
                  .toList();
              if (lines.isEmpty) {
                return Text('No costs entered yet.',
                    style: TextStyle(color: colors?.textMuted));
              }
              double total = 0;
              for (final l in lines) {
                total += l.amountZar;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...lines.map((l) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.description),
                        subtitle: Text(
                            '${l.category.displayLabel}'
                            '${l.invoiceRef != null ? '  •  ${l.invoiceRef}' : ''}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text(
                          'R ${l.amountZar.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                      )),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Total: R ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              );
            },
          ),
        ] else ...[
          // Mechanic sees a neutral cost status — never amounts
          Text(
            switch (record.costStatus) {
              FleetCostStatus.pending => 'Costs pending review.',
              FleetCostStatus.costed => '✓ Costs entered by manager.',
              FleetCostStatus.noCost => 'Reviewed — no costs for this job.',
            },
            style: TextStyle(color: colors?.textMuted, fontSize: 13),
          ),
        ],

        // ── Comments ─────────────────────────────────────────────────────
        const Divider(),
        const Text('Comments',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        _CommentsSection(
          workRecordId: record.id!,
          service: service,
          canComment: canComment,
        ),

        // ── Edit button — admins always; mechanics while uncosted and
        //    within the edit window ────────────────────────────────────────
        if (record.canEdit(isMechanic: isMechanic, isAdmin: isAdmin)) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: Text(mechanicView ? 'Edit this job' : 'Edit Work Record'),
            onPressed: onEdit,
          ),
        ] else if (isMechanic) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: colors?.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.costStatus == FleetCostStatus.pending
                      ? 'Locked — jobs can be edited for '
                          '${FleetWorkRecord.editLockDays} days. '
                          'Use comments for corrections.'
                      : 'Locked — costs have been reviewed. '
                          'Use comments for corrections.',
                  style: TextStyle(color: colors?.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Comments section
// ---------------------------------------------------------------------------

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({
    required this.workRecordId,
    required this.service,
    required this.canComment,
  });

  final String workRecordId;
  final FleetService service;
  final bool canComment;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    final emp = currentEmployee;
    if (text.isEmpty || emp == null) return;
    setState(() => _submitting = true);
    try {
      await widget.service.addComment(
        widget.workRecordId,
        FleetWorkComment(
          text: text,
          authorName: emp.name,
          authorClockNo: emp.clockNo,
          createdAt: DateTime.now(),
        ),
      );
      _ctrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to add comment: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<List<FleetWorkComment>>(
          stream: widget.service.watchComments(widget.workRecordId),
          builder: (context, snapshot) {
            final comments = snapshot.data ?? [];
            if (comments.isEmpty) {
              return Text(
                'No comments yet.',
                style: TextStyle(color: colors?.textMuted, fontSize: 13),
              );
            }
            return Column(
              children: comments
                  .map((c) => _CommentTile(comment: c))
                  .toList(),
            );
          },
        ),
        if (widget.canComment) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Add a comment…',
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.send, color: kBrandOrange),
                      onPressed: _submit,
                      tooltip: 'Send comment',
                    ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final FleetWorkComment comment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final fmt = DateFormat('d MMM yyyy, HH:mm');
    final initial = comment.authorName.isNotEmpty
        ? comment.authorName[0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kBrandOrange.withAlpha(30),
            child: Text(
              initial,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: kBrandOrange),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.authorName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(fmt.format(comment.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: colors?.textMuted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Linked issues list
// ---------------------------------------------------------------------------

class _LinkedIssueList extends StatelessWidget {
  const _LinkedIssueList({
    required this.issueIds,
    required this.service,
    this.mechanicView = false,
  });
  final List<String> issueIds;
  final FleetService service;
  final bool mechanicView;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FleetIssue>>(
      future: Future.wait(issueIds.map(service.getIssue)).then(
        (issues) => issues.whereType<FleetIssue>().toList(),
      ),
      builder: (context, snapshot) {
        final muted =
            Theme.of(context).extension<AppColors>()?.textMuted;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('Loading linked issues…',
              style: TextStyle(color: muted));
        }
        final issues = snapshot.data ?? [];
        if (issues.isEmpty) {
          // Distinct from loading: the linked issues no longer exist.
          return Text('Linked problem not found (it may have been removed).',
              style: TextStyle(color: muted));
        }
        return Column(
          children: issues
              .map((issue) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(issue.assetName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        issue.description.length > 60
                            ? '${issue.description.substring(0, 60)}…'
                            : issue.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FleetIssueDetailScreen(
                            issueId: issue.id!,
                            mechanicMode: mechanicView,
                          ),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row widget
// ---------------------------------------------------------------------------

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
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
            width: 140,
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
