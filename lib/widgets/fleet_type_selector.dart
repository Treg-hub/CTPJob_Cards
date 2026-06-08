import 'package:flutter/material.dart';

import '../models/fleet_type.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import 'fleet_form_fields.dart';

/// Inline picker for fleet [FleetType] rows (work types, asset types, etc.).
class FleetTypeSelector extends StatelessWidget {
  const FleetTypeSelector({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
    this.hintText = 'Select type',
    this.decoration,
    this.validator,
  });

  final String kind;
  final FleetType? value;
  final ValueChanged<FleetType?> onChanged;
  final String hintText;
  final InputDecoration? decoration;
  final FormFieldValidator<FleetType>? validator;

  @override
  Widget build(BuildContext context) {
    final service = FleetService();
    final fieldDecoration =
        decoration ?? fleetDropdownDecoration(hintText: hintText);

    return StreamBuilder<List<FleetType>>(
      stream: service.watchTypes(kind: kind),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const FleetDropdownLoading();
        }

        final types = List<FleetType>.from(snapshot.data ?? [])
          ..sort((a, b) {
            final order = a.sortOrder.compareTo(b.sortOrder);
            return order != 0 ? order : a.label.compareTo(b.label);
          });

        if (types.isEmpty) {
          return InputDecorator(
            decoration: fieldDecoration.copyWith(
              errorText: 'No types configured. Ask admin to add them.',
            ),
            child: Text(
              'No types found',
              style: TextStyle(color: Theme.of(context).appColors.textMuted),
            ),
          );
        }

        final selected = value == null
            ? null
            : types.cast<FleetType?>().firstWhere(
                  (t) => t?.id == value!.id,
                  orElse: () => value,
                );

        if (types.length <= kFleetDropdownThreshold) {
          return DropdownButtonFormField<FleetType>(
            key: ValueKey(selected?.id),
            initialValue: selected,
            isExpanded: true,
            decoration: fieldDecoration,
            hint: Text(hintText),
            items: types
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: onChanged,
            validator: validator,
          );
        }

        return _TypeSheetTriggerField(
          selected: selected,
          hintText: hintText,
          decoration: fieldDecoration,
          types: types,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _TypeSheetTriggerField extends StatelessWidget {
  const _TypeSheetTriggerField({
    required this.selected,
    required this.hintText,
    required this.decoration,
    required this.types,
    required this.onChanged,
  });

  final FleetType? selected;
  final String hintText;
  final InputDecoration decoration;
  final List<FleetType> types;
  final ValueChanged<FleetType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;

    return InkWell(
      onTap: () async {
        final picked = await showFleetTypePickerSheet(
          context,
          types: types,
          selectedId: selected?.id,
          title: decoration.labelText ?? 'Select type',
        );
        if (picked != null) onChanged(picked);
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
                      selected!.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
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

Future<FleetType?> showFleetTypePickerSheet(
  BuildContext context, {
  required List<FleetType> types,
  String? selectedId,
  String title = 'Select type',
}) {
  return showModalBottomSheet<FleetType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _FleetTypePickerSheet(
      types: types,
      selectedId: selectedId,
      title: title,
    ),
  );
}

class _FleetTypePickerSheet extends StatefulWidget {
  const _FleetTypePickerSheet({
    required this.types,
    required this.title,
    this.selectedId,
  });

  final List<FleetType> types;
  final String title;
  final String? selectedId;

  @override
  State<_FleetTypePickerSheet> createState() => _FleetTypePickerSheetState();
}

class _FleetTypePickerSheetState extends State<_FleetTypePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FleetType> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.types;
    return widget.types
        .where((t) => t.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final filtered = _filtered;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

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
                      widget.title,
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
                autofocus: widget.types.length > 8,
                decoration: fleetDropdownDecoration(
                  hintText: 'Search',
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
                        'No types match your search.',
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final type = filtered[index];
                        final isSelected = type.id == widget.selectedId;
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
                            onTap: () => Navigator.pop(context, type),
                            title: Text(
                              type.label,
                              style: const TextStyle(fontWeight: FontWeight.w600),
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