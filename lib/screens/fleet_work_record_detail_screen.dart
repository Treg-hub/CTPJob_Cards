import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_cost_line.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import 'fleet_add_cost_screen.dart';
import 'fleet_issue_detail_screen.dart';
import 'fleet_log_work_screen.dart';

/// Detail view of a single work record.
/// - Mechanic: sees all fields except cost amounts; can edit if no cost lines.
/// - Cost manager/admin: sees full detail including costs; can add cost lines.
class FleetWorkRecordDetailScreen extends ConsumerStatefulWidget {
  final String workRecordId;
  const FleetWorkRecordDetailScreen({super.key, required this.workRecordId});

  @override
  ConsumerState<FleetWorkRecordDetailScreen> createState() =>
      _FleetWorkRecordDetailScreenState();
}

class _FleetWorkRecordDetailScreenState
    extends ConsumerState<FleetWorkRecordDetailScreen> {
  final _service = FleetService();

  @override
  Widget build(BuildContext context) {
    final emp = currentEmployee;
    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;

    final isMechanic = role_utils.isFleetMechanic(emp);
    final isCostMgr = role_utils.isFleetCostManager(emp, settings);
    final isAdmin = role_utils.isFleetAdmin(emp);
    final canSeeCosts = isCostMgr || isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Record'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<FleetWorkRecord?>(
        future: _service.getWorkRecord(widget.workRecordId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final record = snapshot.data;
          if (record == null) {
            return const Center(child: Text('Work record not found.'));
          }
          return _RecordBody(
            record: record,
            isMechanic: isMechanic,
            canSeeCosts: canSeeCosts,
            service: _service,
            onEdit: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FleetLogWorkScreen(
                preSelectedAssetId: record.assetId,
                preSelectedAssetName: record.assetName,
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
    required this.canSeeCosts,
    required this.service,
    required this.onEdit,
    required this.onAddCost,
  });

  final FleetWorkRecord record;
  final bool isMechanic;
  final bool canSeeCosts;
  final FleetService service;
  final VoidCallback onEdit;
  final VoidCallback onAddCost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('d MMM yyyy');
    final colors = Theme.of(context).extension<AppColors>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Work number + title ──────────────────────────────────────────
        Text(record.workNumber,
            style: TextStyle(
                fontFamily: 'monospace',
                color: colors?.textMuted,
                fontSize: 12)),
        const SizedBox(height: 4),
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
        _Row(label: 'Description', child: Text(record.description)),
        _Row(
          label: 'Labour Hours',
          child: Text('${record.labourHours} h'),
        ),
        if (record.machineHoursReading != null)
          _Row(
            label: 'Machine Hours Reading',
            child: Text('${record.machineHoursReading} h'),
          ),
        _Row(
          label: 'Date Range',
          child: Text(
              '${dateFmt.format(record.startDate)} → ${dateFmt.format(record.endDate)}'),
        ),
        _Row(
          label: 'Logged by',
          child: Text(
              '${record.loggedByName} (${record.loggedByClockNo})'),
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
            children: record.photos
                .map((url) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(url,
                          width: 100, height: 100, fit: BoxFit.cover),
                    ))
                .toList(),
          ),
        ],

        // ── Linked issues ────────────────────────────────────────────────
        if (record.linkedIssueIds.isNotEmpty) ...[
          const Divider(),
          const Text('Linked Issues',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: record.linkedIssueIds
                .map((id) => ActionChip(
                      label: Text(id.substring(0, 8),
                          style: const TextStyle(fontSize: 11)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                FleetIssueDetailScreen(issueId: id)),
                      ),
                    ))
                .toList(),
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
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18, color: kBrandOrange),
                label: const Text('Add Cost',
                    style: TextStyle(color: kBrandOrange)),
                onPressed: onAddCost,
              ),
            ],
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
          // Mechanic sees a neutral cost status
          Text(
            record.hasCostLines
                ? '✓ Costs entered by manager.'
                : 'Costs pending review.',
            style: TextStyle(color: colors?.textMuted, fontSize: 13),
          ),
        ],

        // ── Edit button (mechanic, only if no cost lines) ─────────────────
        if (isMechanic && !record.hasCostLines) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit Work Record'),
            onPressed: onEdit,
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

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
