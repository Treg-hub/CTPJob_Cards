import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fleet_issue.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_constants.dart';
import 'fleet_form_fields.dart';
import 'fleet_work_form_sections.dart';

/// Shared work-capture fields used by Mark-as-Fixed and Log-other-work screens.
class FleetWorkCaptureForm extends StatelessWidget {
  const FleetWorkCaptureForm({
    super.key,
    required this.descCtrl,
    required this.machineHoursCtrl,
    required this.labourHoursCtrl,
    required this.workCarriedOut,
    required this.dateFmt,
    required this.workDateIsToday,
    required this.onPickWorkDate,
    required this.parts,
    required this.suggestedPartNames,
    required this.onAddPart,
    required this.onAddPartSuggestion,
    required this.onRemovePart,
    required this.pendingPhotoPaths,
    required this.onAddPhoto,
    required this.onRemovePendingPhoto,
    this.lastRecordedHours,
    this.otherOpenIssues = const [],
    this.linkedIssueIds = const [],
    this.onLinkedIssueToggle,
    this.descAutofocus = false,
    this.descHint = 'Describe the work carried out.',
  });

  final TextEditingController descCtrl;
  final TextEditingController machineHoursCtrl;
  final TextEditingController labourHoursCtrl;
  final DateTime workCarriedOut;
  final DateFormat dateFmt;
  final bool workDateIsToday;
  final VoidCallback onPickWorkDate;
  final List<FleetWorkPartRow> parts;
  final List<String> suggestedPartNames;
  final VoidCallback onAddPart;
  final void Function(String name) onAddPartSuggestion;
  final void Function(int index) onRemovePart;
  final List<String> pendingPhotoPaths;
  final Future<void> Function() onAddPhoto;
  final void Function(String path) onRemovePendingPhoto;
  final double? lastRecordedHours;
  final List<FleetIssue> otherOpenIssues;
  final List<String> linkedIssueIds;
  final void Function(FleetIssue issue, bool selected)? onLinkedIssueToggle;
  final bool descAutofocus;
  final String descHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FleetSectionLabel('Work carried out on'),
        FleetWorkDatesCard(
          workCarriedOut: workCarriedOut,
          dateFmt: dateFmt,
          workDateIsToday: workDateIsToday,
          onEdit: onPickWorkDate,
        ),
        const SizedBox(height: 16),
        const FleetSectionLabel('What you did *'),
        TextField(
          controller: descCtrl,
          maxLines: 4,
          autofocus: descAutofocus,
          decoration: fleetDropdownDecoration(hintText: descHint),
        ),
        const SizedBox(height: 16),
        const FleetSectionLabel('Machine hour-meter reading *'),
        TextField(
          controller: machineHoursCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fleetDropdownDecoration(
            hintText: 'Reading on the hour meter',
          ),
        ),
        if (lastRecordedHours != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Last recorded: ${fleetFormatHours(lastRecordedHours!)} h',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).appColors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: 16),
        const FleetSectionLabel('Labour hours (optional)'),
        TextField(
          controller: labourHoursCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fleetDropdownDecoration(hintText: 'e.g. 2.5'),
        ),
        const SizedBox(height: 16),
        FleetWorkPhotosSection(
          savedPhotoUrls: const [],
          pendingPhotoPaths: pendingPhotoPaths,
          onAddPhoto: onAddPhoto,
          onRemoveSaved: (_) {},
          onRemovePending: onRemovePendingPhoto,
          maxPhotos: kFleetMaxPhotos,
          hint: 'Photos of the finished work (optional).',
        ),
        const SizedBox(height: 16),
        FleetWorkPartsSection(
          parts: parts,
          optional: true,
          suggestedPartNames: suggestedPartNames,
          onAdd: onAddPart,
          onAddSuggestion: onAddPartSuggestion,
          onRemove: onRemovePart,
        ),
        if (otherOpenIssues.isNotEmpty && onLinkedIssueToggle != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: FleetSectionLabel('Also fixes these reported problems?'),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: kBrandOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${otherOpenIssues.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            linkedIssueIds.length > 1
                ? '${linkedIssueIds.length - 1} selected to close with this fix'
                : 'Tick any other open problems this job also fixes',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).appColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          ...otherOpenIssues.map((issue) {
            final ticked = linkedIssueIds.contains(issue.id);
            return CheckboxListTile(
              value: ticked,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                issue.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                'Reported by ${issue.reportedByName}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).appColors.textMuted,
                ),
              ),
              onChanged: (v) => onLinkedIssueToggle!(issue, v ?? false),
            );
          }),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}