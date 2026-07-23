import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../utils/fleet_constants.dart';
import 'fleet_form_fields.dart';

/// Shared work-form UI sections used by mark-fixed, log-other, and edit screens.

class FleetWorkDatesCard extends StatelessWidget {
  const FleetWorkDatesCard({
    super.key,
    required this.workCarriedOut,
    required this.dateFmt,
    required this.workDateIsToday,
    required this.onEdit,
  });

  final DateTime workCarriedOut;
  final DateFormat dateFmt;
  final bool workDateIsToday;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.engineering_outlined,
                  size: 16, color: kBrandOrange),
              const SizedBox(width: 8),
              const Text('Work carried out',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(dateFmt.format(workCarriedOut),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  if (!workDateIsToday)
                    Text('Different from today',
                        style: TextStyle(
                            fontSize: 10, color: Colors.orange.shade700)),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit, size: 14, color: kBrandOrange),
            ],
          ),
        ),
      ),
    );
  }
}

class FleetWorkPartRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
}

class FleetWorkPartsSection extends StatelessWidget {
  const FleetWorkPartsSection({
    super.key,
    required this.parts,
    required this.onAdd,
    required this.onRemove,
    required this.onAddSuggestion,
    required this.suggestedPartNames,
    this.optional = false,
  });

  final List<FleetWorkPartRow> parts;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(String partName) onAddSuggestion;
  final List<String> suggestedPartNames;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final usedNames = parts.map((r) => r.nameCtrl.text.trim()).toSet();
    final availableChips =
        suggestedPartNames.where((n) => !usedNames.contains(n)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FleetSectionLabel(
              optional ? 'Parts used (optional)' : 'Parts Used',
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Part'),
              onPressed: onAdd,
            ),
          ],
        ),
        if (availableChips.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick picks:',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).appColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: availableChips
                      .take(kFleetCommonPartNames.length)
                      .map((name) => ActionChip(
                            label: Text(name,
                                style: const TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.add, size: 14),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onAddSuggestion(name),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
        ...parts.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _FleetPartNameField(
                    controller: row.nameCtrl,
                    suggestedPartNames: suggestedPartNames,
                    usedNames: usedNames,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: fleetDropdownDecoration(
                      hintText: 'Qty',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Part name field with autocomplete chips filtered as the user types.
class _FleetPartNameField extends StatefulWidget {
  const _FleetPartNameField({
    required this.controller,
    required this.suggestedPartNames,
    required this.usedNames,
  });

  final TextEditingController controller;
  final List<String> suggestedPartNames;
  final Set<String> usedNames;

  @override
  State<_FleetPartNameField> createState() => _FleetPartNameFieldState();
}

class _FleetPartNameFieldState extends State<_FleetPartNameField> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final next = widget.controller.text;
    if (next != _query) setState(() => _query = next);
  }

  List<String> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.suggestedPartNames
        .where((name) {
          final lower = name.toLowerCase();
          return lower.contains(q) &&
              lower != q &&
              !widget.usedNames.contains(name);
        })
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final muted = Theme.of(context).appColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          decoration: fleetDropdownDecoration(
            hintText: 'Part name',
            isDense: true,
          ),
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: matches
                .map((name) => ActionChip(
                      label: Text(name, style: const TextStyle(fontSize: 11)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        widget.controller.text = name;
                        widget.controller.selection = TextSelection.collapsed(
                            offset: name.length);
                        setState(() => _query = name);
                      },
                    ))
                .toList(),
          ),
          Text(
            'Common Hyster parts & past jobs',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ],
    );
  }
}

class FleetWorkPhotosSection extends StatelessWidget {
  const FleetWorkPhotosSection({
    super.key,
    required this.savedPhotoUrls,
    required this.pendingPhotoPaths,
    required this.onAddPhoto,
    required this.onRemoveSaved,
    required this.onRemovePending,
    this.hint,
    this.maxPhotos = kFleetMaxPhotos,
  });

  final List<String> savedPhotoUrls;
  final List<String> pendingPhotoPaths;
  final Future<void> Function() onAddPhoto;
  final void Function(String url) onRemoveSaved;
  final void Function(String path) onRemovePending;
  final String? hint;
  final int maxPhotos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FleetSectionLabel('Photos (optional, max $maxPhotos)'),
        if (hint != null) ...[
          Text(
            hint!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).appColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          children: [
            ...savedPhotoUrls.map((url) => _FleetWorkPhotoThumb(
                  image: Image.network(url,
                      width: 80, height: 80, fit: BoxFit.cover),
                  onRemove: () => onRemoveSaved(url),
                )),
            ...pendingPhotoPaths.map((path) => _FleetWorkPhotoThumb(
                  image: Image.file(File(path),
                      width: 80, height: 80, fit: BoxFit.cover),
                  onRemove: () => onRemovePending(path),
                )),
            if (savedPhotoUrls.length + pendingPhotoPaths.length < maxPhotos)
              GestureDetector(
                onTap: onAddPhoto,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_a_photo, color: Colors.grey),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FleetWorkPhotoThumb extends StatelessWidget {
  const _FleetWorkPhotoThumb({required this.image, required this.onRemove});
  final Widget image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: image,
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

String fleetFormatHours(double hours) => hours % 1 == 0
    ? hours.toStringAsFixed(0)
    : hours.toStringAsFixed(1);