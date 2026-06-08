import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/fleet_asset.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_record.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_cost_widgets.dart';
import '../widgets/fleet_filter_dropdown.dart';
import 'fleet_add_cost_screen.dart';
import 'fleet_work_record_detail_screen.dart';

/// Work records list with asset and work-type filters.
class FleetWorkRecordsListScreen extends ConsumerStatefulWidget {
  /// Cost-manager tab: last 50 jobs, highlight uncosted, tap to add cost.
  final bool embedded;
  final bool costManagerMode;
  final bool mechanicMode;

  /// @deprecated Use [costManagerMode] instead.
  final bool costsPendingOnly;

  const FleetWorkRecordsListScreen({
    super.key,
    this.embedded = false,
    this.costManagerMode = false,
    this.mechanicMode = false,
    this.costsPendingOnly = false,
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
  String? _costStatusFilter; // null = all, 'pending', 'costed'
  List<FleetAsset> _assets = [];
  List<FleetType> _workTypes = [];

  bool get _isCostTab => widget.costManagerMode || widget.costsPendingOnly;

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

    if (widget.costsPendingOnly && !widget.costManagerMode) {
      filtered = filtered.where((r) => !r.hasCostLines).toList();
    } else if (_isCostTab && _costStatusFilter == 'pending') {
      filtered = filtered.where((r) => !r.hasCostLines).toList();
    } else if (_isCostTab && _costStatusFilter == 'costed') {
      filtered = filtered.where((r) => r.hasCostLines).toList();
    }

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
        if (_isCostTab) const FleetCostJobsGuideBanner(),
        if (_isCostTab)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _CostFilterChip(
                  label: 'All jobs',
                  selected: _costStatusFilter == null,
                  onTap: () => setState(() => _costStatusFilter = null),
                ),
                const SizedBox(width: 8),
                _CostFilterChip(
                  label: 'Needs costing',
                  selected: _costStatusFilter == 'pending',
                  onTap: () => setState(() => _costStatusFilter = 'pending'),
                ),
                const SizedBox(width: 8),
                _CostFilterChip(
                  label: 'Costed',
                  selected: _costStatusFilter == 'costed',
                  onTap: () => setState(() => _costStatusFilter = 'costed'),
                ),
              ],
            ),
          ),
        if (!_isCostTab || widget.costManagerMode)
          Padding(
            padding: EdgeInsets.fromLTRB(12, _isCostTab ? 0 : 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: FleetFilterDropdown<String>(
                    labelText: widget.mechanicMode || _isCostTab
                        ? 'Forklift'
                        : 'Asset',
                    allLabel: widget.mechanicMode || _isCostTab
                        ? 'All forklifts'
                        : 'All assets',
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
                    labelText: widget.mechanicMode || _isCostTab
                        ? 'Job type'
                        : 'Work type',
                    allLabel: widget.mechanicMode || _isCostTab
                        ? 'All job types'
                        : 'All types',
                    value: _workTypeFilterId,
                    options: _workTypes
                        .map(
                          (t) => FleetFilterOption(
                            value: t.id!,
                            label: t.label,
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _workTypeFilterId = v),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<FleetWorkRecord>>(
            stream: _service.watchWorkRecords(
              assetId: _assetFilterId,
              limit: _isCostTab ? 50 : 100,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final allRecords = snapshot.data ?? [];
              final records = _applyFilters(allRecords);
              final pendingCount =
                  allRecords.where((r) => !r.hasCostLines).length;

              if (records.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _isCostTab
                          ? (_costStatusFilter == 'pending'
                              ? (pendingCount == 0
                                  ? 'All jobs are costed. Well done!'
                                  : 'No uncosted jobs match these filters.')
                              : _costStatusFilter == 'costed'
                                  ? 'No costed jobs match these filters.'
                                  : 'No jobs match these filters.')
                          : widget.mechanicMode
                              ? (_assetFilterId != null ||
                                      _workTypeFilterId != null
                                  ? 'No jobs match these filters.'
                                  : 'No jobs logged yet.\nFix a problem from To Fix, or tap below to log other work.')
                              : 'No work records match these filters.\nTap "Log Work" to add one.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) => WorkRecordTile(
                  record: records[index],
                  mechanicMode: widget.mechanicMode,
                  costManagerMode: _isCostTab,
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

class _CostFilterChip extends StatelessWidget {
  const _CostFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: kBrandOrange,
      labelStyle: TextStyle(color: selected ? Colors.white : null),
      onSelected: (_) => onTap(),
    );
  }
}

/// Shared work record tile used in list view and Fleet Home.
class WorkRecordTile extends StatelessWidget {
  const WorkRecordTile({
    super.key,
    required this.record,
    this.mechanicMode = false,
    this.costManagerMode = false,
  });

  final FleetWorkRecord record;
  final bool mechanicMode;
  final bool costManagerMode;

  void _onTap(BuildContext context) {
    if (costManagerMode) {
      if (!record.hasCostLines) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FleetAddCostScreen(
              preSelectedAssetId: record.assetId,
              preSelectedAssetName: record.assetName,
              preSelectedWorkRecordId: record.id,
              preSelectedWorkNumber: record.workNumber,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FleetWorkRecordDetailScreen(
              workRecordId: record.id!,
            ),
          ),
        );
      }
      return;
    }
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
    final needsCosting = costManagerMode && !record.hasCostLines;

    return Card(
      color: needsCosting
          ? kBrandOrange.withValues(alpha: 0.06)
          : colors?.cardSurface,
      shape: needsCosting
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: kBrandOrange.withValues(alpha: 0.55)),
            )
          : null,
      child: ListTile(
        onTap: () => _onTap(context),
        leading: CircleAvatar(
          backgroundColor: needsCosting ? kBrandOrange : kBrandOrange,
          foregroundColor: Colors.white,
          child: Icon(
            costManagerMode
                ? (record.hasCostLines
                    ? Icons.check_circle_outline
                    : Icons.receipt_outlined)
                : Icons.build,
            size: 18,
          ),
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
            if (costManagerMode)
              Text(
                'By ${record.loggedByName}',
                style: TextStyle(color: colors?.textMuted, fontSize: 11),
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (!mechanicMode)
                  Text(
                    record.workNumber,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: colors?.textMuted,
                      fontSize: 11,
                    ),
                  ),
                const Spacer(),
                if (!mechanicMode || record.labourHours > 0)
                  Text(
                    mechanicMode
                        ? '${record.labourHours} h labour'
                        : '${record.labourHours} h',
                    style: TextStyle(
                      color: colors?.textMuted,
                      fontSize: 11,
                    ),
                  ),
                if (!mechanicMode || record.labourHours > 0)
                  const SizedBox(width: 8),
                Text(
                  dateFmt.format(record.startDate),
                  style: TextStyle(
                    color: colors?.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                if (costManagerMode)
                  FleetCostStatusBadge(hasCostLines: record.hasCostLines)
                else if (!mechanicMode && record.hasCostLines)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Costed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (costManagerMode)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  record.hasCostLines
                      ? 'Tap to view job and add more costs'
                      : 'Tap to enter costs for this job',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: record.hasCostLines
                        ? colors?.textMuted
                        : kBrandOrange,
                  ),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}