import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_type.dart';
import '../main.dart' show currentEmployee;
import '../models/fleet_work_record.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_filter_dropdown.dart';
import 'fleet_work_record_detail_screen.dart';

/// Mechanic work history list with asset and work-type filters.
class FleetWorkRecordsListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final bool mechanicMode;

  const FleetWorkRecordsListScreen({
    super.key,
    this.embedded = false,
    this.mechanicMode = true,
  });

  @override
  ConsumerState<FleetWorkRecordsListScreen> createState() =>
      _FleetWorkRecordsListScreenState();
}

class _FleetWorkRecordsListScreenState
    extends ConsumerState<FleetWorkRecordsListScreen> {
  final _service = FleetService();
  String? _assetFilterId;
  String? _workTypeFilterId;
  List<FleetAsset> _assets = [];
  List<FleetType> _workTypes = [];

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    final assets = await _service.watchAssets().first;
    final types = await _service.watchTypes(kind: 'work_type').first;
    if (mounted) {
      setState(() {
        _assets = assets;
        _workTypes = types;
      });
    }
  }

  List<FleetWorkRecord> _applyFilters(List<FleetWorkRecord> records) {
    var filtered = records;
    if (_assetFilterId != null) {
      filtered =
          filtered.where((r) => r.assetId == _assetFilterId).toList();
    }
    if (_workTypeFilterId != null) {
      filtered = filtered
          .where((r) => r.workTypeId == _workTypeFilterId)
          .toList();
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: FleetFilterDropdown<String>(
                  labelText: 'Machine',
                  allLabel: 'All machines',
                  value: _assetFilterId,
                  options: _assets
                      .map(
                        (a) => FleetFilterOption(
                          value: a.id!,
                          label: a.name,
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _assetFilterId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FleetFilterDropdown<String>(
                  labelText: 'Job type',
                  allLabel: 'All job types',
                  value: _workTypeFilterId,
                  options: _workTypes
                      .map(
                        (t) => FleetFilterOption(
                          value: t.id!,
                          label: t.label,
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _workTypeFilterId = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<FleetWorkRecord>>(
            stream: _service.watchWorkRecords(
              assetId: _assetFilterId,
              loggedByClockNo: widget.mechanicMode
                  ? currentEmployee?.clockNo
                  : null,
              limit: 100,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = _applyFilters(snapshot.data ?? []);

              if (records.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _assetFilterId != null || _workTypeFilterId != null
                          ? 'No jobs match these filters.'
                          : 'No jobs logged yet.\nFix a problem from To Fix, or use Log work.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: ScreenInsets.listPadding(
                  context,
                  horizontal: 12,
                  top: 12,
                  inHomeShell: widget.embedded,
                ),
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => WorkRecordTile(
                  record: records[index],
                  mechanicMode: widget.mechanicMode,
                ),
              );
            },
          ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: const FleetAppBar(title: 'Work Records'),
      body: body,
    );
  }
}

/// Shared work record tile for mechanic history lists.
class WorkRecordTile extends StatelessWidget {
  const WorkRecordTile({
    super.key,
    required this.record,
    this.mechanicMode = true,
  });

  final FleetWorkRecord record;
  final bool mechanicMode;

  void _onTap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FleetWorkRecordDetailScreen(
          workRecordId: record.id!,
          mechanicMode: mechanicMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final dateFmt = DateFormat('d MMM');

    return Card(
      color: colors?.cardSurface,
      child: ListTile(
        onTap: () => _onTap(context),
        leading: const CircleAvatar(
          backgroundColor: kBrandOrange,
          foregroundColor: Colors.white,
          child: Icon(Icons.build, size: 18),
        ),
        title: Text(
          record.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${record.assetName}  •  ${record.workTypeName}',
              style: TextStyle(color: colors?.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Spacer(),
                if (record.labourHours > 0)
                  Text(
                    '${record.labourHours} h labour',
                    style: TextStyle(
                      color: colors?.textMuted,
                      fontSize: 11,
                    ),
                  ),
                if (record.labourHours > 0) const SizedBox(width: 8),
                Text(
                  dateFmt.format(record.startDate),
                  style: TextStyle(
                    color: colors?.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}