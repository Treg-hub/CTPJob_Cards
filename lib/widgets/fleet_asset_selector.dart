import 'package:flutter/material.dart';

import '../models/fleet_asset.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import 'fleet_form_fields.dart';

/// Inline asset picker for fleet forms.
///
/// Uses a [DropdownButtonFormField] when there are at most [kFleetDropdownThreshold]
/// assets; otherwise opens a searchable bottom sheet so users stay on the form.
class FleetAssetSelector extends StatelessWidget {

  const FleetAssetSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeOnly = true,
    this.decoration,
  });

  final FleetAsset? value;
  final ValueChanged<FleetAsset?> onChanged;
  final bool activeOnly;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final service = FleetService();
    final defaultDecoration =
        decoration ?? fleetDropdownDecoration(hintText: 'Select asset');

    return StreamBuilder<List<FleetAsset>>(
      stream: service.watchAssets(activeOnly: activeOnly),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const FleetDropdownLoading();
        }

        final assets = List<FleetAsset>.from(snapshot.data ?? [])
          ..sort((a, b) => a.name.compareTo(b.name));

        if (assets.isEmpty) {
          return InputDecorator(
            decoration: defaultDecoration.copyWith(
              errorText: 'No assets available. Ask admin to add assets.',
            ),
            child: Text(
              'No assets found',
              style: TextStyle(
                color: Theme.of(context).appColors.textMuted,
              ),
            ),
          );
        }

        final selected = value == null
            ? null
            : assets.cast<FleetAsset?>().firstWhere(
                  (a) => a?.id == value!.id,
                  orElse: () => value,
                );

        if (assets.length <= kFleetDropdownThreshold) {
          return DropdownButtonFormField<FleetAsset>(
            key: ValueKey(selected?.id),
            initialValue: selected,
            isExpanded: true,
            decoration: defaultDecoration,
            hint: const Text('Select asset'),
            items: assets
                .map(
                  (asset) => DropdownMenuItem(
                    value: asset,
                    child: _AssetOptionLabel(asset: asset, compact: true),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          );
        }

        return _SheetTriggerField(
          selected: selected,
          decoration: defaultDecoration,
          onTap: () async {
            final picked = await showFleetAssetPickerSheet(
              context,
              assets: assets,
              selectedId: selected?.id,
            );
            if (picked != null) onChanged(picked);
          },
        );
      },
    );
  }
}

/// Searchable bottom sheet for choosing an asset without leaving the form.
Future<FleetAsset?> showFleetAssetPickerSheet(
  BuildContext context, {
  List<FleetAsset>? assets,
  String? selectedId,
  bool activeOnly = true,
}) async {
  final list = assets ??
      await FleetService().watchAssets(activeOnly: activeOnly).first;
  if (!context.mounted) return null;

  return showModalBottomSheet<FleetAsset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _FleetAssetPickerSheet(
      assets: List<FleetAsset>.from(list)
        ..sort((a, b) => a.name.compareTo(b.name)),
      selectedId: selectedId,
    ),
  );
}

class _SheetTriggerField extends StatelessWidget {
  const _SheetTriggerField({
    required this.selected,
    required this.decoration,
    required this.onTap,
  });

  final FleetAsset? selected;
  final InputDecoration decoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: decoration,
        child: Row(
          children: [
            Icon(
              Icons.forklift,
              size: 20,
              color: selected != null
                  ? Theme.of(context).colorScheme.primary
                  : muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: selected == null
                  ? Text('Tap to choose asset', style: TextStyle(color: muted))
                  : _AssetOptionLabel(asset: selected!),
            ),
            Icon(Icons.arrow_drop_down, color: muted),
          ],
        ),
      ),
    );
  }
}

class _FleetAssetPickerSheet extends StatefulWidget {
  const _FleetAssetPickerSheet({
    required this.assets,
    this.selectedId,
  });

  final List<FleetAsset> assets;
  final String? selectedId;

  @override
  State<_FleetAssetPickerSheet> createState() => _FleetAssetPickerSheetState();
}

class _FleetAssetPickerSheetState extends State<_FleetAssetPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FleetAsset> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.assets;
    return widget.assets.where((a) {
      return a.name.toLowerCase().contains(q) ||
          a.assetTag.toLowerCase().contains(q) ||
          a.typeName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final filtered = _filtered;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

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
                      'Select asset',
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
                autofocus: widget.assets.length > 8,
                decoration: fleetDropdownDecoration(
                  hintText: 'Search by name, tag, or type',
                  isDense: true,
                ).copyWith(prefixIcon: const Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No assets match your search.',
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final asset = filtered[index];
                        final isSelected = asset.id == widget.selectedId;
                        return Material(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.08)
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
                                  : BorderSide.none,
                            ),
                            onTap: () => Navigator.pop(context, asset),
                            leading: _AssetAvatar(asset: asset),
                            title: _AssetOptionLabel(asset: asset),
                            subtitle: Text(
                              '${asset.typeName}  •  ${asset.assetTag}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
                              ),
                            ),
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

class _AssetOptionLabel extends StatelessWidget {
  const _AssetOptionLabel({required this.asset, this.compact = false});

  final FleetAsset asset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Flexible(
          child: Text(
            asset.name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: compact ? 14 : 15,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (asset.hasOpenOosIssue) ...[
          const SizedBox(width: 8),
          _OosBadge(errorColor: theme.colorScheme.error),
        ],
      ],
    );
  }
}

class _AssetAvatar extends StatelessWidget {
  const _AssetAvatar({required this.asset});

  final FleetAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = asset.hasOpenOosIssue
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return CircleAvatar(
      backgroundColor: bg,
      foregroundColor: onColor(bg),
      radius: 20,
      child: Icon(
        asset.typeName.toLowerCase().contains('grab')
            ? Icons.precision_manufacturing
            : Icons.forklift,
        size: 20,
      ),
    );
  }
}

class _OosBadge extends StatelessWidget {
  const _OosBadge({required this.errorColor});

  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: errorColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'OOS',
        style: TextStyle(
          color: onColor(errorColor),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}