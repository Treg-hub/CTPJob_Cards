import 'package:flutter/material.dart';

import '../models/fleet_work_record.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import 'fleet_cost_widgets.dart';
import 'fleet_form_fields.dart';

const _workRecordNoneSentinel = _WorkRecordNoneSentinel();

class _WorkRecordNoneSentinel {
  const _WorkRecordNoneSentinel();
}

String fleetWorkRecordLabel(FleetWorkRecord record) {
  final title = record.title.length > 25
      ? '${record.title.substring(0, 25)}…'
      : record.title;
  return '${record.workNumber}  $title';
}

/// Links a cost line (or other record) to an optional work record for one asset.
class FleetWorkRecordSelector extends StatelessWidget {
  const FleetWorkRecordSelector({
    super.key,
    required this.assetId,
    required this.value,
    required this.onChanged,
    this.allowNone = true,
    this.hintText = 'Link to a work record (optional)',
    this.decoration,
    this.showCostStatus = false,
  });

  final String? assetId;
  final FleetWorkRecord? value;
  final ValueChanged<FleetWorkRecord?> onChanged;
  final bool allowNone;
  final String hintText;
  final InputDecoration? decoration;
  final bool showCostStatus;

  @override
  Widget build(BuildContext context) {
    final fieldDecoration =
        decoration ?? fleetDropdownDecoration(hintText: hintText);

    if (assetId == null) {
      return InputDecorator(
        decoration: fieldDecoration,
        child: Text(
          'Select an asset first',
          style: TextStyle(color: Theme.of(context).appColors.textMuted),
        ),
      );
    }

    final service = FleetService();
    return StreamBuilder<List<FleetWorkRecord>>(
      stream: service.watchWorkRecords(assetId: assetId, limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const FleetDropdownLoading();
        }

        final records = List<FleetWorkRecord>.from(snapshot.data ?? [])
          ..sort((a, b) => b.startDate.compareTo(a.startDate));

        if (records.isEmpty) {
          return InputDecorator(
            decoration: fieldDecoration,
            child: Text(
              'No work records for this asset',
              style: TextStyle(color: Theme.of(context).appColors.textMuted),
            ),
          );
        }

        final selected = value == null
            ? null
            : records.cast<FleetWorkRecord?>().firstWhere(
                  (r) => r?.id == value!.id,
                  orElse: () => value,
                );

        if (records.length <= kFleetDropdownThreshold) {
          return DropdownButtonFormField<FleetWorkRecord?>(
            key: ValueKey('${assetId}_${selected?.id}'),
            initialValue: selected,
            isExpanded: true,
            decoration: fieldDecoration,
            hint: Text(hintText),
            items: [
              if (allowNone)
                const DropdownMenuItem<FleetWorkRecord?>(
                  value: null,
                  child: Text('None'),
                ),
              ...records.map(
                (record) => DropdownMenuItem(
                  value: record,
                  child: Text(
                    fleetWorkRecordLabel(record),
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          );
        }

        return _WorkRecordSheetTriggerField(
          selected: selected,
          hintText: hintText,
          decoration: fieldDecoration,
          records: records,
          allowNone: allowNone,
          showCostStatus: showCostStatus,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _WorkRecordSheetTriggerField extends StatelessWidget {
  const _WorkRecordSheetTriggerField({
    required this.selected,
    required this.hintText,
    required this.decoration,
    required this.records,
    required this.allowNone,
    required this.onChanged,
    this.showCostStatus = false,
  });

  final FleetWorkRecord? selected;
  final String hintText;
  final InputDecoration decoration;
  final List<FleetWorkRecord> records;
  final bool allowNone;
  final ValueChanged<FleetWorkRecord?> onChanged;
  final bool showCostStatus;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;

    return InkWell(
      onTap: () async {
        final result = await showFleetWorkRecordPickerSheet(
          context,
          records: records,
          selectedId: selected?.id,
          allowNone: allowNone,
          showCostStatus: showCostStatus,
        );
        if (result == null) return;
        if (result == _workRecordNoneSentinel) {
          onChanged(null);
        } else if (result is FleetWorkRecord) {
          onChanged(result);
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: decoration,
        child: Row(
          children: [
            Expanded(
              child: selected == null
                  ? Text(hintText, style: TextStyle(color: muted))
                  : Text(
                      fleetWorkRecordLabel(selected!),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            Icon(Icons.arrow_drop_down, color: muted),
          ],
        ),
      ),
    );
  }
}

Future<Object?> showFleetWorkRecordPickerSheet(
  BuildContext context, {
  required List<FleetWorkRecord> records,
  String? selectedId,
  bool allowNone = true,
  bool showCostStatus = false,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _FleetWorkRecordPickerSheet(
      records: records,
      selectedId: selectedId,
      allowNone: allowNone,
      showCostStatus: showCostStatus,
    ),
  );
}

class _FleetWorkRecordPickerSheet extends StatefulWidget {
  const _FleetWorkRecordPickerSheet({
    required this.records,
    this.selectedId,
    this.allowNone = true,
    this.showCostStatus = false,
  });

  final List<FleetWorkRecord> records;
  final String? selectedId;
  final bool allowNone;
  final bool showCostStatus;

  @override
  State<_FleetWorkRecordPickerSheet> createState() =>
      _FleetWorkRecordPickerSheetState();
}

class _FleetWorkRecordPickerSheetState
    extends State<_FleetWorkRecordPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FleetWorkRecord> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.records;
    return widget.records.where((r) {
      return r.workNumber.toLowerCase().contains(q) ||
          r.title.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final filtered = _filtered;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.65;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.showCostStatus
                          ? 'Link to a mechanic job'
                          : 'Select work record',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: widget.records.length > 8,
                decoration: fleetDropdownDecoration(
                  hintText: 'Search by number or title',
                  isDense: true,
                ).copyWith(prefixIcon: const Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.allowNone)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: widget.selectedId == null
                        ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
                        : BorderSide.none,
                  ),
                  tileColor: widget.selectedId == null
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : colors.cardSurface,
                  onTap: () => Navigator.pop(context, _workRecordNoneSentinel),
                  title: const Text('None'),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No work records match your search.',
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final record = filtered[index];
                        final isSelected = record.id == widget.selectedId;
                        final needsCosting = widget.showCostStatus &&
                            record.costStatus == FleetCostStatus.pending;
                        return Material(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.08)
                              : needsCosting
                                  ? kBrandOrange.withValues(alpha: 0.06)
                                  : colors.cardSurface,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: isSelected
                                  ? BorderSide(
                                      color: theme.colorScheme.primary,
                                      width: 1.5,
                                    )
                                  : needsCosting
                                      ? BorderSide(
                                          color: kBrandOrange
                                              .withValues(alpha: 0.5),
                                        )
                                      : BorderSide.none,
                            ),
                            onTap: () => Navigator.pop(context, record),
                            title: Text(
                              record.title,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${record.workNumber} · ${record.assetName}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
                              ),
                            ),
                            trailing: widget.showCostStatus
                                ? FleetCostStatusBadge(
                                    costStatus: record.costStatus,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}