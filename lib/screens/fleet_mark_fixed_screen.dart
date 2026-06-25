import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_part.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_issue_summary_card.dart';
import '../widgets/fleet_work_form_sections.dart';

/// Minimal fix-a-fault screen — description + meter required; rest in "More details".
class FleetMarkFixedScreen extends ConsumerStatefulWidget {
  final String preSelectedAssetId;
  final String? preSelectedAssetName;
  final String linkedIssueId;

  const FleetMarkFixedScreen({
    super.key,
    required this.preSelectedAssetId,
    this.preSelectedAssetName,
    required this.linkedIssueId,
  });

  @override
  ConsumerState<FleetMarkFixedScreen> createState() =>
      _FleetMarkFixedScreenState();
}

class _FleetMarkFixedScreenState extends ConsumerState<FleetMarkFixedScreen> {
  final _service = FleetService();
  final _descCtrl = TextEditingController();
  final _labourHoursCtrl = TextEditingController();
  final _machineHoursCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetIssue? _linkedIssue;
  FleetType? _repairWorkType;
  List<FleetIssue> _otherOpenIssues = [];
  final List<String> _pendingPhotoPaths = [];
  List<String> _linkedIssueIds = [];
  final List<FleetWorkPartRow> _parts = [];
  List<String> _suggestedPartNames = [];
  DateTime _workCarriedOut = DateTime.now();
  bool _saving = false;
  bool _moreExpanded = false;
  bool _alsoFixesExpanded = false;

  @override
  void initState() {
    super.initState();
    _linkedIssueIds = [widget.linkedIssueId];
    _loadAsset();
    _loadLinkedIssue(widget.linkedIssueId);
    _loadSuggestedParts();
    _loadWorkTypes();
  }

  Future<void> _loadAsset() async {
    final asset = await _service.getAsset(widget.preSelectedAssetId);
    if (asset != null && mounted) {
      setState(() => _selectedAsset = asset);
      _loadOtherOpenIssues();
    }
  }

  Future<void> _loadLinkedIssue(String issueId) async {
    final issue = await _service.watchIssue(issueId).first;
    if (!mounted || issue == null) return;
    setState(() {
      _linkedIssue = issue;
      if (issue.acknowledgedAt != null) {
        _workCarriedOut = issue.acknowledgedAt!;
      }
    });
    if (issue.status == FleetIssueStatus.open) {
      final emp = currentEmployee;
      if (emp != null) {
        _service
            .acknowledgeIssue(issue.id!, emp.clockNo, emp.name)
            .catchError((_) {});
      }
    }
  }

  Future<void> _loadOtherOpenIssues() async {
    final asset = _selectedAsset;
    if (asset?.id == null) return;
    final issues = await _service.watchIssues(assetId: asset!.id).first;
    if (!mounted) return;
    setState(() {
      _otherOpenIssues = issues
          .where((i) => i.status.isOpen && i.id != widget.linkedIssueId)
          .toList();
      if (_otherOpenIssues.isNotEmpty) {
        _alsoFixesExpanded = true;
      }
    });
  }

  Future<void> _loadSuggestedParts() async {
    final names = await _service.getSuggestedPartNames();
    if (mounted) setState(() => _suggestedPartNames = names);
  }

  Future<void> _loadWorkTypes() async {
    final types = await _service.watchTypes(kind: 'work_type').first;
    if (!mounted) return;
    final repair =
        types.where((t) => t.label.toLowerCase().contains('repair'));
    setState(() {
      _repairWorkType = repair.isNotEmpty ? repair.first : types.firstOrNull;
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _labourHoursCtrl.dispose();
    _machineHoursCtrl.dispose();
    for (final p in _parts) {
      p.nameCtrl.dispose();
      p.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickWorkDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _workCarriedOut,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_workCarriedOut),
    );
    if (time == null || !mounted) return;
    setState(() {
      _workCarriedOut = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      );
    });
  }

  Future<void> _addPhoto() async {
    if (_pendingPhotoPaths.length >= 5) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final path = await _service.pickAndCompressPhoto(source);
    if (path != null && mounted) setState(() => _pendingPhotoPaths.add(path));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final emp = currentEmployee;
    if (emp == null || _selectedAsset == null || _repairWorkType == null) {
      _showError('Still loading — try again in a moment.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showError('Please describe what you did to fix it.');
      return;
    }
    final machineHours =
        double.tryParse(_machineHoursCtrl.text.replaceAll(',', '.'));
    if (machineHours == null) {
      _showError('Please enter the machine hour-meter reading.');
      return;
    }
    final labourHours = _labourHoursCtrl.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_labourHoursCtrl.text.replaceAll(',', '.'));
    if (labourHours == null || labourHours < 0) {
      _showError('Labour hours must be a valid number (or leave blank).');
      return;
    }

    final lastReading = _selectedAsset?.currentMachineHours;
    if (lastReading != null && machineHours < lastReading) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reading lower than last recorded'),
          content: Text(
            'Last recorded: ${fleetFormatHours(lastReading)} h\n'
            'You entered: ${fleetFormatHours(machineHours)} h\n\n'
            'Save anyway?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go back')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save anyway')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final desc = _descCtrl.text.trim();
    final title =
        desc.length > 60 ? desc.substring(0, 60) : 'Fix: ${_selectedAsset!.name}';

    setState(() => _saving = true);
    try {
      final partModels = _parts
          .map((row) {
            final name = row.nameCtrl.text.trim();
            if (name.isEmpty) return null;
            return FleetWorkPart(
              partName: name,
              quantity: int.tryParse(row.qtyCtrl.text.trim()),
            );
          })
          .whereType<FleetWorkPart>()
          .toList();

      await _service.createWorkRecordResilient(
        {
          'asset_id': _selectedAsset!.id,
          'asset_name': _selectedAsset!.name,
          'work_type_id': _repairWorkType!.id,
          'work_type_name': _repairWorkType!.label,
          'title': title,
          'description': desc,
          'labour_hours': labourHours,
          'machine_hours_reading': machineHours,
          'photos': <String>[],
          'start_date': _workCarriedOut.toIso8601String(),
          'end_date': DateTime.now().toIso8601String(),
          'logged_by_clock_no': emp.clockNo,
          'logged_by_name': emp.name,
          'linked_issue_ids': _linkedIssueIds,
        },
        photoPaths: _pendingPhotoPaths,
        parts: partModels,
        linkedIssueIds: _linkedIssueIds,
        loggedByClockNo: emp.clockNo,
        loggedByName: emp.name,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Problem marked as fixed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');
    final now = DateTime.now();
    final workDateIsToday = _workCarriedOut.year == now.year &&
        _workCarriedOut.month == now.month &&
        _workCarriedOut.day == now.day;

    return Scaffold(
      appBar: const FleetAppBar(title: 'Mark as Fixed'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_saving ? 'Saving…' : 'Mark as Fixed'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_linkedIssue != null) ...[
            FleetIssueSummaryCard(issue: _linkedIssue!),
            const SizedBox(height: 16),
          ],

          const FleetSectionLabel('What you did to fix it *'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            autofocus: true,
            decoration: fleetDropdownDecoration(
              hintText: 'Describe the work YOU did — the fault is shown above.',
            ),
          ),
          const SizedBox(height: 16),

          const FleetSectionLabel('Machine hour-meter reading *'),
          TextField(
            controller: _machineHoursCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fleetDropdownDecoration(
              hintText: 'Reading on the hour meter',
            ),
          ),
          if (_selectedAsset?.currentMachineHours != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Last recorded: ${fleetFormatHours(_selectedAsset!.currentMachineHours!)} h',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).appColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 16),

          if (_otherOpenIssues.isNotEmpty)
            ExpansionTile(
              initiallyExpanded: _alsoFixesExpanded,
              onExpansionChanged: (v) =>
                  setState(() => _alsoFixesExpanded = v),
              tilePadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Also fixes these reported problems?',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kBrandOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_otherOpenIssues.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                _linkedIssueIds.length > 1
                    ? '${_linkedIssueIds.length - 1} selected to close with this fix'
                    : 'Tick any other open problems this job also fixes',
                style: const TextStyle(fontSize: 12),
              ),
              children: [
                ..._otherOpenIssues.map((issue) {
                  final ticked = _linkedIssueIds.contains(issue.id);
                  return CheckboxListTile(
                    value: ticked,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(issue.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      'Reported by ${issue.reportedByName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).appColors.textMuted,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _linkedIssueIds.add(issue.id!);
                        } else {
                          _linkedIssueIds.remove(issue.id);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),

          ExpansionTile(
            initiallyExpanded: _moreExpanded,
            onExpansionChanged: (v) => setState(() => _moreExpanded = v),
            title: const Text(
              'More details (optional)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Labour hours, parts, photos, work date',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              const SizedBox(height: 8),
              FleetWorkDatesCard(
                workCarriedOut: _workCarriedOut,
                dateFmt: dateFmt,
                workDateIsToday: workDateIsToday,
                onEdit: _pickWorkDate,
              ),
              const SizedBox(height: 16),
              const FleetSectionLabel('Labour hours (optional)'),
              TextField(
                controller: _labourHoursCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fleetDropdownDecoration(hintText: 'e.g. 2.5'),
              ),
              const SizedBox(height: 16),
              FleetWorkPartsSection(
                parts: _parts,
                optional: true,
                suggestedPartNames: _suggestedPartNames,
                onAdd: () => setState(() => _parts.add(FleetWorkPartRow())),
                onAddSuggestion: (name) {
                  setState(() {
                    final row = FleetWorkPartRow();
                    row.nameCtrl.text = name;
                    _parts.add(row);
                  });
                },
                onRemove: (i) {
                  setState(() {
                    _parts[i].nameCtrl.dispose();
                    _parts[i].qtyCtrl.dispose();
                    _parts.removeAt(i);
                  });
                },
              ),
              const SizedBox(height: 16),
              FleetWorkPhotosSection(
                savedPhotoUrls: const [],
                pendingPhotoPaths: _pendingPhotoPaths,
                onAddPhoto: _addPhoto,
                onRemoveSaved: (_) {},
                onRemovePending: (path) =>
                    setState(() => _pendingPhotoPaths.remove(path)),
                hint: 'Photos of the finished work (optional, max 5).',
              ),
              const SizedBox(height: 16),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}