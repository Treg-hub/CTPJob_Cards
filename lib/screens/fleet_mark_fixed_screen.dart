import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_part.dart';
import '../services/fleet_service.dart';
import '../utils/fleet_constants.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_work_photo_utils.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_issue_summary_card.dart';
import '../widgets/fleet_work_capture_form.dart';
import '../widgets/fleet_work_form_sections.dart';
import '../utils/screen_insets.dart';

/// Fix-a-fault screen — Save progress (ack) or Mark as Fixed (work record).
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
  List<String> _suggestedPartNames = List.of(kFleetCommonPartNames);
  DateTime _workCarriedOut = DateTime.now();
  bool _saving = false;
  bool _savingProgress = false;

  @override
  void initState() {
    super.initState();
    _linkedIssueIds = [widget.linkedIssueId];
    _loadAsset();
    _loadLinkedIssue(widget.linkedIssueId);
    _loadSuggestedParts();
    _loadWorkTypes();
    _descCtrl.addListener(_onFormChanged);
    _machineHoursCtrl.addListener(_onFormChanged);
    _labourHoursCtrl.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _formDirty =>
      _descCtrl.text.trim().isNotEmpty ||
      _machineHoursCtrl.text.trim().isNotEmpty ||
      _labourHoursCtrl.text.trim().isNotEmpty ||
      _pendingPhotoPaths.isNotEmpty ||
      _parts.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (!_formDirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text(
          'You have unsaved changes. Use Save progress if you are starting a multi-day job.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
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
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _addPhoto() async {
    if (!guardPersonaSubmit(context)) return;
    final path = await pickFleetCompressedPhoto(
      context,
      _service,
      currentCount: _pendingPhotoPaths.length,
    );
    if (path != null && mounted) setState(() => _pendingPhotoPaths.add(path));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveProgress() async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    final issue = _linkedIssue;
    if (emp == null || issue?.id == null) return;
    final actor = resolveWriteActor(emp)!;
    if (issue!.status != FleetIssueStatus.open) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _savingProgress = true);
    try {
      await _service.acknowledgeIssue(issue.id!, actor.clockNo, actor.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Marked in progress — finish the repair when done.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not save progress: $e');
      }
    } finally {
      if (mounted) setState(() => _savingProgress = false);
    }
  }

  Future<void> _save() async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    if (emp == null || _selectedAsset == null || _repairWorkType == null) {
      _showError('Still loading — try again in a moment.');
      return;
    }
    final actor = resolveWriteActor(emp)!;
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
    final title = desc.length > 60
        ? desc.substring(0, 60)
        : 'Fix: ${_selectedAsset!.name}';

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
          'logged_by_clock_no': actor.clockNo,
          'logged_by_name': actor.name,
          'linked_issue_ids': _linkedIssueIds,
        },
        photoPaths: _pendingPhotoPaths,
        parts: partModels,
        linkedIssueIds: _linkedIssueIds,
        loggedByClockNo: actor.clockNo,
        loggedByName: actor.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Problem marked as fixed.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
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
    final showSaveProgress =
        _linkedIssue?.status == FleetIssueStatus.open;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: FleetAppBar(
          title: 'Mark as Fixed',
          isOnSite: realEmployee?.isOnSite,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSaveProgress)
                  OutlinedButton.icon(
                    onPressed: (_saving || _savingProgress) ? null : _saveProgress,
                    icon: _savingProgress
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.pause_circle_outline),
                    label: Text(_savingProgress
                        ? 'Saving…'
                        : 'Save progress & come back later'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                if (showSaveProgress) const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: (_saving || _savingProgress) ? null : _save,
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
              ],
            ),
          ),
        ),
        body: ListView(
          padding: ScreenInsets.symmetricScroll(context),
          children: [
            if (_linkedIssue != null) ...[
              FleetIssueSummaryCard(issue: _linkedIssue!),
              const SizedBox(height: 16),
            ],
            FleetWorkCaptureForm(
              descCtrl: _descCtrl,
              machineHoursCtrl: _machineHoursCtrl,
              labourHoursCtrl: _labourHoursCtrl,
              workCarriedOut: _workCarriedOut,
              dateFmt: dateFmt,
              workDateIsToday: workDateIsToday,
              onPickWorkDate: _pickWorkDate,
              parts: _parts,
              suggestedPartNames: _suggestedPartNames,
              onAddPart: () => setState(() => _parts.add(FleetWorkPartRow())),
              onAddPartSuggestion: (name) {
                setState(() {
                  final row = FleetWorkPartRow();
                  row.nameCtrl.text = name;
                  _parts.add(row);
                });
              },
              onRemovePart: (i) {
                setState(() {
                  _parts[i].nameCtrl.dispose();
                  _parts[i].qtyCtrl.dispose();
                  _parts.removeAt(i);
                });
              },
              pendingPhotoPaths: _pendingPhotoPaths,
              onAddPhoto: _addPhoto,
              onRemovePendingPhoto: (path) =>
                  setState(() => _pendingPhotoPaths.remove(path)),
              lastRecordedHours: _selectedAsset?.currentMachineHours,
              otherOpenIssues: _otherOpenIssues,
              linkedIssueIds: _linkedIssueIds,
              onLinkedIssueToggle: (issue, selected) {
                setState(() {
                  if (selected) {
                    _linkedIssueIds.add(issue.id!);
                  } else {
                    _linkedIssueIds.remove(issue.id);
                  }
                });
              },
              descAutofocus: true,
              descHint:
                  'Describe the work YOU did — the fault is shown above.',
            ),
          ],
        ),
      ),
    );
  }
}