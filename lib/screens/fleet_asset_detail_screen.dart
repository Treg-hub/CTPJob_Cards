import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_work_record.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_issue_widgets.dart';
import 'fleet_issue_detail_screen.dart';
import 'fleet_work_records_list_screen.dart' show WorkRecordTile;

/// Everything about one Hyster on a single page: status, hour meter,
/// service-due state, open problems, work history, and (for cost
/// managers/admins) total spend. The natural home for the preventive
/// maintenance phase.
class FleetAssetDetailScreen extends ConsumerStatefulWidget {
  final String assetId;
  const FleetAssetDetailScreen({super.key, required this.assetId});

  @override
  ConsumerState<FleetAssetDetailScreen> createState() =>
      _FleetAssetDetailScreenState();
}

class _FleetAssetDetailScreenState
    extends ConsumerState<FleetAssetDetailScreen> {
  final _service = FleetService();

  @override
  Widget build(BuildContext context) {
    final emp = currentEmployee;
    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;
    final isMechanic = role_utils.isFleetMechanic(emp, settings);
    final isAdmin = role_utils.isFleetAdmin(emp);

    return Scaffold(
      appBar: const FleetAppBar(title: 'Hyster Details'),
      body: StreamBuilder<FleetAsset?>(
        stream: _service.watchAsset(widget.assetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final asset = snapshot.data;
          if (asset == null) {
            return const Center(child: Text('Asset not found.'));
          }
          return _AssetBody(
            asset: asset,
            service: _service,
            isMechanic: isMechanic,
            isAdmin: isAdmin,
          );
        },
      ),
    );
  }
}

class _AssetBody extends StatelessWidget {
  const _AssetBody({
    required this.asset,
    required this.service,
    required this.isMechanic,
    required this.isAdmin,
  });

  final FleetAsset asset;
  final FleetService service;
  final bool isMechanic;
  final bool isAdmin;

  static String _fmtHours(double h) =>
      h % 1 == 0 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final dateFmt = DateFormat('d MMM yyyy');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Text(asset.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(asset.typeName,
                  style: const TextStyle(fontSize: 12)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text('Tag: ${asset.assetTag}',
                  style: const TextStyle(fontSize: 12)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            if (asset.serial != null)
              Chip(
                label: Text('S/N: ${asset.serial}',
                    style: const TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            if (asset.hasOpenOosIssue)
              Chip(
                label: const Text('OUT OF SERVICE',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                backgroundColor: Colors.red,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            if (!asset.active)
              Chip(
                label:
                    const Text('Inactive', style: TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Hour meter + service status ────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 18, color: kBrandOrange),
                    const SizedBox(width: 8),
                    Text(
                      asset.currentMachineHours != null
                          ? 'Hour meter: ${_fmtHours(asset.currentMachineHours!)} h'
                          : 'Hour meter: no reading yet',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (asset.serviceDue)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.build_circle_outlined,
                          size: 18, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Service due — ${asset.serviceDueReason}',
                          style: TextStyle(
                            color: Colors.amber.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (asset.serviceIntervalHours != null ||
                    asset.serviceIntervalDays != null)
                  Text(
                    [
                      if (asset.serviceIntervalHours != null)
                        'Service every ${_fmtHours(asset.serviceIntervalHours!)} h',
                      if (asset.serviceIntervalDays != null)
                        'every ${asset.serviceIntervalDays} days',
                      if (asset.lastServiceDate != null)
                        'last: ${dateFmt.format(asset.lastServiceDate!)}',
                    ].join('  •  '),
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  )
                else
                  Text(
                    isAdmin
                        ? 'No service intervals set — add them via Edit.'
                        : 'No service intervals set.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Open problems ──────────────────────────────────────────────
        const Text('Open problems',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        StreamBuilder<List<FleetIssue>>(
          stream: service.watchAssetIssues(asset.id!),
          builder: (context, snapshot) {
            final open = (snapshot.data ?? [])
                .where((i) => i.status.isOpen)
                .toList();
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (open.isEmpty) {
              return Text('No open problems.',
                  style: TextStyle(color: colors.textMuted, fontSize: 13));
            }
            return Column(
              children: [
                for (final issue in open)
                  FleetIssueTile(
                    issue: issue,
                    mechanicMode: isMechanic,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FleetIssueDetailScreen(
                          issueId: issue.id!,
                          mechanicMode: isMechanic,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // ── Work history ───────────────────────────────────────────────
        const Text('Work history',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        StreamBuilder<List<FleetWorkRecord>>(
          stream: service.watchWorkRecords(assetId: asset.id, limit: 20),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return Text('No work logged yet.',
                  style: TextStyle(color: colors.textMuted, fontSize: 13));
            }
            return Column(
              children: [
                for (final record in records)
                  WorkRecordTile(
                    record: record,
                    mechanicMode: isMechanic,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}
