import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_part.dart';
import '../models/fleet_work_record.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_selector.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_issue_summary_card.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_type_selector.dart';
import 'fleet_work_record_detail_screen.dart';

/// Mechanic (and admin) work logging screen.
/// Optionally pre-populated with an asset and/or linked issue.
class FleetLogWorkScreen extends ConsumerStatefulWidget {
  final String? preSelectedAssetId;
  final String? preSelectedAssetName;
  final String? linkedIssueId;
  final String? workRecordId;

  const FleetLogWorkScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedAssetName,
    this.linkedIssueId,
    this.workRecordId,
  });

  @override
  ConsumerState<FleetLogWorkScreen> createState() => _FleetLogWorkScreenState();
}

class _FleetLogWorkScreenState extends ConsumerState<FleetLogWorkScreen> {
  final _service = FleetService();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _labourHoursCtrl = TextEditingController();
  final _machineHoursCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetType? _selectedWorkType;
  FleetIssue? _linkedIssue;

  // Other open faults on the selected asset — the mechanic can tick them
  // so one job closes several reports at once.
  List<FleetIssue> _otherOpenIssues = [];
  final List<String> _savedPhotoUrls = [];
  final List<String> _pendingPhotoPaths = [];
  List<String> _linkedIssueIds = [];
  bool _saving = false;
  bool _loading = false;

  // The date/time the work was actually carried out — always shown at top and editable.
  DateTime _workCarriedOut = DateTime.now();

  // Parts in progress
  final List<_PartRow> _parts = [];

  // Part name suggestions for quick-add chips
  List<String> _suggestedPartNames = [];

  // End date loaded from an existing record (preserved on edit).
  DateTime? _loadedEndDate;

  bool get _isEditing => widget.workRecordId != null;
  bool get _isFixingIssue => !_isEditing && widget.linkedIssueId != null;
  bool get _isLogOtherWork => !_isEditing && !_isFixingIssue;

  @override
  void initState() {
    super.initState();
    _loadWorkTypes();
    _loadSuggestedParts();
    if (widget.workRecordId != null) {
      _loadExistingRecord(widget.workRecordId!);
    } else {
      if (widget.preSelectedAssetId != null) {
        _service.getAsset(widget.preSelectedAssetId!).then((a) {
          if (a != null && mounted) {
            setState(() => _selectedAsset = a);
            _loadOtherOpenIssues();
          }
        });
      }
      if (widget.linkedIssueId != null) {
        _linkedIssueIds = [widget.linkedIssueId!];
        _loadLinkedIssue(widget.linkedIssueId!);
      }
    }
  }

  /// Loads open faults on the selected asset (excluding the one being
  /// fixed) so the mechanic can close them with the same job.
  Future<void> _loadOtherOpenIssues() async {
    final asset = _selectedAsset;
    if (asset == null || asset.id == null || _isEditing) {
      if (mounted && _otherOpenIssues.isNotEmpty) {
        setState(() => _otherOpenIssues = []);
      }
      return;
    }
    final issues = await _service.watchIssues(assetId: asset.id).first;
    if (!mounted || _selectedAsset?.id != asset.id) return;
    setState(() {
      _otherOpenIssues = issues
          .where((i) => i.status.isOpen && i.id != widget.linkedIssueId)
          .toList();
      // Drop ticked faults that no longer apply to this asset.
      _linkedIssueIds = _linkedIssueIds
          .where((id) =>
              id == widget.linkedIssueId ||
              _otherOpenIssues.any((i) => i.id == id))
          .toList();
    });
  }

  Future<void> _loadSuggestedParts() async {
    final names = await _service.getSuggestedPartNames();
    if (mounted) setState(() => _suggestedPartNames = names);
  }

  Future<void> _loadLinkedIssue(String issueId) async {
    final issue = await _service.watchIssue(issueId).first;
    if (!mounted || issue == null) return;
    setState(() {
      _linkedIssue = issue;
      if (_titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = 'Fix: ${issue.assetName}';
      }
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

  Future<void> _loadExistingRecord(String id) async {
    setState(() => _loading = true);
    try {
      final record = await _service.getWorkRecord(id);
      if (record == null) return;

      // Guard deep links: locked records can only be viewed or commented on.
      final settings = await _service.getSettings();
      final canEdit = record.canEdit(
        isMechanic: role_utils.isFleetMechanic(currentEmployee, settings),
        isAdmin: role_utils.isFleetAdmin(currentEmployee),
      );
      if (!canEdit) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                record.costStatus == FleetCostStatus.pending
                    ? 'This job is locked — jobs can be edited for '
                        '${FleetWorkRecord.editLockDays} days. '
                        'Add a comment for corrections.'
                    : 'This job is locked because costs have been entered. '
                        'Add a comment for corrections.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final parts = await _service.watchParts(id).first;
      final asset = await _service.getAsset(record.assetId);
      if (!mounted) return;
      setState(() {
        _selectedAsset = asset;
        _titleCtrl.text = record.title;
        _descCtrl.text = record.description;
        _labourHoursCtrl.text = record.labourHours.toString();
        if (record.machineHoursReading != null) {
          _machineHoursCtrl.text = record.machineHoursReading.toString();
        }
        _workCarriedOut = record.startDate;
        _loadedEndDate = record.endDate;
        _savedPhotoUrls
          ..clear()
          ..addAll(record.photos);
        _linkedIssueIds = List.from(record.linkedIssueIds);
        _parts
          ..clear()
          ..addAll(parts.map((p) {
            final row = _PartRow();
            row.nameCtrl.text = p.partName;
            if (p.quantity != null) row.qtyCtrl.text = p.quantity.toString();
            return row;
          }));
      });
      final types = await _service.watchTypes(kind: 'work_type').first;
      if (mounted) {
        setState(() {
          _selectedWorkType = types
                  .where((t) => t.id == record.workTypeId)
                  .firstOrNull ??
              types.firstOrNull;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _labourHoursCtrl.dispose();
    _machineHoursCtrl.dispose();
    super.dispose();
  }

  FleetType? _pickDefaultWorkType(List<FleetType> types) {
    if (types.isEmpty) return null;
    final repair =
        types.where((t) => t.label.toLowerCase().contains('repair'));
    return repair.isNotEmpty ? repair.first : types.first;
  }

  Future<void> _loadWorkTypes() async {
    if (_isEditing) return;
    final types = await _service.watchTypes(kind: 'work_type').first;
    if (mounted && _selectedWorkType == null) {
      setState(() {
        _selectedWorkType = _isFixingIssue
            ? _pickDefaultWorkType(types)
            : types.firstOrNull;
      });
    }
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
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _addPhoto() async {
    if (_savedPhotoUrls.length + _pendingPhotoPaths.length >= 5) return;
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

    final localPath = await _service.pickAndCompressPhoto(source);
    if (localPath == null) return;
    if (mounted) setState(() => _pendingPhotoPaths.add(localPath));
  }

  Future<void> _save() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (_selectedAsset == null) {
      _showError('Please pick which machine you worked on.');
      return;
    }
    if (_selectedWorkType == null) {
      _showError('Please pick a job type.');
      return;
    }
    if (!_isFixingIssue && _titleCtrl.text.trim().isEmpty) {
      _showError('Please enter a short title for the work.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showError(_isFixingIssue
          ? 'Please describe what you did to fix it.'
          : 'Please describe what was done.');
      return;
    }
    final labourHours = _labourHoursCtrl.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_labourHoursCtrl.text.replaceAll(',', '.'));
    if (labourHours == null || labourHours < 0) {
      _showError('Labour hours must be a valid number (or leave blank).');
      return;
    }
    final machineHours =
        double.tryParse(_machineHoursCtrl.text.replaceAll(',', '.'));
    if (machineHours == null) {
      _showError('Please enter the machine hour-meter reading.');
      return;
    }
    if (_parts.any((p) => p.nameCtrl.text.trim().isEmpty)) {
      _showError('All part rows must have a part name.');
      return;
    }

    // Hour meters only count up — confirm an intentionally lower reading
    // (e.g. after a meter swap) instead of silently accepting a typo.
    if (!_isEditing) {
      final lastReading = _selectedAsset?.currentMachineHours;
      if (lastReading != null && machineHours < lastReading) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reading lower than last recorded'),
            content: Text(
              'The hour meter usually only counts up.\n\n'
              'Last recorded: ${_formatHours(lastReading)} h\n'
              'You entered: ${_formatHours(machineHours)} h\n\n'
              'Save anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go back'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
    }

    // Auto-generate title in fix mode — the description carries the detail.
    if (_isFixingIssue && _titleCtrl.text.trim().isEmpty) {
      final desc = _descCtrl.text.trim();
      _titleCtrl.text = desc.length > 60
          ? desc.substring(0, 60)
          : 'Fix: ${_selectedAsset!.name}';
    }

    setState(() => _saving = true);
    try {
      final startDate = _workCarriedOut;
      final endDate =
          _isEditing ? (_loadedEndDate ?? DateTime.now()) : DateTime.now();
      final parts = _parts
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

      String recordId;
      String? workNumber;
      var queuedOffline = false;
      if (_isEditing) {
        recordId = widget.workRecordId!;
        // Re-check server state — the detail screen's Edit button gating is
        // advisory only; costs may have been entered or the 14-day window
        // passed since this form was opened.
        final fresh = await _service.getWorkRecord(recordId);
        if (fresh == null) {
          _showError('Could not load this job — check your connection and try again.');
          return;
        }
        if (fresh.hasCostLines) {
          _showError('Costs have been entered for this job — it can no longer be edited.');
          return;
        }
        if (fresh.isEditLocked) {
          _showError(
            'This job is locked — records can\'t be edited after ${FleetWorkRecord.editLockDays} days.',
          );
          return;
        }
        final uploaded = await _service.uploadPhotosForRecord(
            recordId, _pendingPhotoPaths);
        final allPhotos = [..._savedPhotoUrls, ...uploaded];
        await _service.updateWorkRecord(recordId, {
          'asset_id': _selectedAsset!.id,
          'asset_name': _selectedAsset!.name,
          'work_type_id': _selectedWorkType!.id,
          'work_type_name': _selectedWorkType!.label,
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'labour_hours': labourHours,
          'machine_hours_reading': machineHours,
          'photos': allPhotos,
          'start_date': Timestamp.fromDate(startDate),
          'end_date': Timestamp.fromDate(endDate),
          'linked_issue_ids': _linkedIssueIds,
        });
        await _service.replaceParts(recordId, parts);
      } else {
        final data = {
          'asset_id': _selectedAsset!.id,
          'asset_name': _selectedAsset!.name,
          'work_type_id': _selectedWorkType!.id,
          'work_type_name': _selectedWorkType!.label,
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'labour_hours': labourHours,
          'machine_hours_reading': machineHours,
          'photos': <String>[],
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'logged_by_clock_no': emp.clockNo,
          'logged_by_name': emp.name,
          'linked_issue_ids': _linkedIssueIds,
        };

        final result = await _service.createWorkRecordResilient(
          data,
          photoPaths: _pendingPhotoPaths,
          parts: parts,
          linkedIssueIds: _linkedIssueIds,
          loggedByClockNo: emp.clockNo,
          loggedByName: emp.name,
        );
        recordId = result.id;
        workNumber = result.workNumber;
        queuedOffline = result.queuedOffline;
      }

      if (mounted) {
        if (_isEditing) {
          Navigator.of(context).pop();
        } else if (_isFixingIssue) {
          Navigator.of(context).pop(true);
        } else if (queuedOffline) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                // workNumber present = record created, only attachments
                // (photos/parts) are still queued.
                workNumber != null
                    ? 'Job $workNumber saved — photos/parts will finish syncing.'
                    : 'Work saved offline — will sync when connection returns.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          final settings = ref.read(fleetSettingsProvider).asData?.value ??
              FleetSettings.defaults;
          final mechanicUx = role_utils.isFleetMechanic(
                  currentEmployee, settings) &&
              !role_utils.isFleetAdmin(currentEmployee);
          if (mechanicUx) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Job saved. See it in History.'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => FleetWorkRecordDetailScreen(
                  workRecordId: recordId,
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatHours(double hours) => hours % 1 == 0
      ? hours.toStringAsFixed(0)
      : hours.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');
    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;
    final mechanicUx = role_utils.isFleetMechanic(currentEmployee, settings) &&
        !role_utils.isFleetAdmin(currentEmployee);
    final useMechanicLabels = mechanicUx && !_isFixingIssue;

    if (_loading) {
      return Scaffold(
        appBar: FleetAppBar(
          title: _isEditing
              ? (mechanicUx ? 'Edit job' : 'Edit Work')
              : (mechanicUx ? 'Log other work' : 'Log Work'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final showBottomSave = _isFixingIssue || (_isLogOtherWork && mechanicUx);

    // Whether the work date differs from today (highlights backdating).
    final now = DateTime.now();
    final workDateIsToday = _workCarriedOut.year == now.year &&
        _workCarriedOut.month == now.month &&
        _workCarriedOut.day == now.day;

    return Scaffold(
      appBar: FleetAppBar(
        title: _isFixingIssue
            ? 'Mark as Fixed'
            : (_isEditing
                ? (mechanicUx ? 'Edit job' : 'Edit Work')
                : (mechanicUx ? 'Log other work' : 'Log Work')),
        actions: [
          if (!showBottomSave)
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: _save,
                style: TextButton.styleFrom(foregroundColor: Colors.black),
                child: const Text('Save'),
              ),
        ],
      ),
      bottomNavigationBar: showBottomSave
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_isFixingIssue
                          ? Icons.check_circle_outline
                          : Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : (_isFixingIssue ? 'Mark as Fixed' : 'Save job'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isLogOtherWork && mechanicUx) ...[
            const FleetMechanicGuideBanner.logOtherWork(),
            const SizedBox(height: 16),
          ],

          // ── Reported fault (read-only) — fix mode only ─────────────────
          if (_isFixingIssue && _linkedIssue != null) ...[
            FleetIssueSummaryCard(issue: _linkedIssue!),
            const SizedBox(height: 8),
            Text(
              'Saving will record your fix against this report and mark it '
              'as fixed.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).appColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Dates card ─────────────────────────────────────────────────
          _WorkDatesCard(
            workCarriedOut: _workCarriedOut,
            dateFmt: dateFmt,
            workDateIsToday: workDateIsToday,
            onEdit: _pickWorkDate,
          ),
          const SizedBox(height: 16),

          // ── Asset (hidden in fix mode — shown in the reported fault card) ──
          if (!_isFixingIssue) ...[
            FleetSectionLabel(
              useMechanicLabels
                  ? 'Which machine? (forks, grab or BT) *'
                  : 'Asset *',
            ),
            FleetAssetSelector(
              value: _selectedAsset,
              onChanged: (asset) {
                setState(() => _selectedAsset = asset);
                _loadOtherOpenIssues();
              },
            ),
            const SizedBox(height: 16),
          ],

          // ── Also fixes: other open faults on this asset ────────────────
          if (!_isEditing && _otherOpenIssues.isNotEmpty) ...[
            FleetSectionLabel(
              _isFixingIssue
                  ? 'Also fixes these reported problems?'
                  : 'Does this job fix any reported problems?',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Tick the reports this job closes — they will be marked '
                'as fixed when you save.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).appColors.textMuted,
                ),
              ),
            ),
            ..._otherOpenIssues.map((issue) {
              final ticked = _linkedIssueIds.contains(issue.id);
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
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      if (!_linkedIssueIds.contains(issue.id)) {
                        _linkedIssueIds.add(issue.id!);
                      }
                    } else {
                      _linkedIssueIds.remove(issue.id);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 16),
          ],

          if (!_isFixingIssue) ...[
            FleetSectionLabel(useMechanicLabels ? 'Job type *' : 'Work Type *'),
            if (useMechanicLabels)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'e.g. Routine service, Repair, Overhaul, Inspection',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).appColors.textMuted,
                  ),
                ),
              ),
            FleetTypeSelector(
              kind: 'work_type',
              value: _selectedWorkType,
              hintText: useMechanicLabels ? 'Pick job type' : 'Select work type',
              onChanged: (type) => setState(() => _selectedWorkType = type),
            ),
            const SizedBox(height: 16),
          ],

          // ── Title (hidden in fix mode — auto-generated from description) ──
          if (!_isFixingIssue) ...[
            FleetSectionLabel(
              useMechanicLabels ? 'What you did (short title) *' : 'Title *',
            ),
            TextField(
              controller: _titleCtrl,
              decoration: fleetDropdownDecoration(
                hintText: useMechanicLabels
                    ? 'e.g. Transmission replacement'
                    : 'e.g. Engine oil change + filter',
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Description ───────────────────────────────────────────────
          FleetSectionLabel(
            _isFixingIssue
                ? 'What you did to fix it *'
                : (useMechanicLabels
                    ? 'Details of the work *'
                    : 'Description *'),
          ),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: fleetDropdownDecoration(
              hintText: _isFixingIssue
                  ? 'Describe the work YOU did — the fault report is shown above.'
                  : (useMechanicLabels
                      ? 'Describe the work carried out.'
                      : 'Describe what was done.'),
            ),
          ),
          const SizedBox(height: 16),

          // ── Machine hours (required) ──────────────────────────────────
          const FleetSectionLabel('Machine hour-meter reading *'),
          TextField(
            controller: _machineHoursCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: fleetDropdownDecoration(
              hintText: 'Reading on the hour meter',
            ),
          ),
          if (_selectedAsset?.currentMachineHours != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Last recorded: ${_formatHours(_selectedAsset!.currentMachineHours!)} h',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).appColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // ── Labour hours (optional) ───────────────────────────────────
          const FleetSectionLabel('Labour hours (optional)'),
          TextField(
            controller: _labourHoursCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: fleetDropdownDecoration(hintText: 'e.g. 2.5'),
          ),
          const SizedBox(height: 16),

          _PartsSection(
            parts: _parts,
            optional: useMechanicLabels || _isFixingIssue,
            suggestedPartNames: _suggestedPartNames,
            onAdd: () => setState(() => _parts.add(_PartRow())),
            onAddSuggestion: (name) {
              setState(() {
                final row = _PartRow();
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
          _PhotosSection(
            savedPhotoUrls: _savedPhotoUrls,
            pendingPhotoPaths: _pendingPhotoPaths,
            onAddPhoto: _addPhoto,
            onRemoveSaved: (url) =>
                setState(() => _savedPhotoUrls.remove(url)),
            onRemovePending: (path) =>
                setState(() => _pendingPhotoPaths.remove(path)),
            hint: useMechanicLabels || _isFixingIssue
                ? 'Photos of the finished work (optional, max 5).'
                : null,
          ),
          SizedBox(height: showBottomSave ? 100 : 80),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dates card
// ---------------------------------------------------------------------------

class _WorkDatesCard extends StatelessWidget {
  const _WorkDatesCard({
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
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
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

// ---------------------------------------------------------------------------
// Parts section with quick-add chips
// ---------------------------------------------------------------------------

class _PartsSection extends StatelessWidget {
  const _PartsSection({
    required this.parts,
    required this.onAdd,
    required this.onRemove,
    required this.onAddSuggestion,
    required this.suggestedPartNames,
    this.optional = false,
  });

  final List<_PartRow> parts;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(String partName) onAddSuggestion;
  final List<String> suggestedPartNames;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    // Parts already added — filter chips so we don't suggest already-used names.
    final usedNames = parts.map((r) => r.nameCtrl.text.trim()).toSet();
    final availableChips = suggestedPartNames
        .where((n) => !usedNames.contains(n))
        .toList();

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
        // Quick-add chips from previously-used parts
        if (availableChips.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick add:',
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
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.nameCtrl,
                    decoration: fleetDropdownDecoration(
                      hintText: 'Part name',
                      isDense: true,
                    ),
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

// ---------------------------------------------------------------------------
// Photos section
// ---------------------------------------------------------------------------

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({
    required this.savedPhotoUrls,
    required this.pendingPhotoPaths,
    required this.onAddPhoto,
    required this.onRemoveSaved,
    required this.onRemovePending,
    this.hint,
  });

  final List<String> savedPhotoUrls;
  final List<String> pendingPhotoPaths;
  final Future<void> Function() onAddPhoto;
  final void Function(String url) onRemoveSaved;
  final void Function(String path) onRemovePending;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FleetSectionLabel('Photos (optional, max 5)'),
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
            ...savedPhotoUrls.map((url) => _PhotoThumb(
                  image: Image.network(url,
                      width: 80, height: 80, fit: BoxFit.cover),
                  onRemove: () => onRemoveSaved(url),
                )),
            ...pendingPhotoPaths.map((path) => _PhotoThumb(
                  image: Image.file(File(path),
                      width: 80, height: 80, fit: BoxFit.cover),
                  onRemove: () => onRemovePending(path),
                )),
            if (savedPhotoUrls.length + pendingPhotoPaths.length < 5)
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

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.image, required this.onRemove});
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
              child:
                  const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _PartRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
}
