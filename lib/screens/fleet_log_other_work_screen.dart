import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../utils/fleet_constants.dart';
import '../utils/fleet_work_photo_utils.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_part.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_selector.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_mechanic_widgets.dart';
import '../widgets/fleet_type_selector.dart';
import '../widgets/fleet_work_form_sections.dart';
import 'fleet_work_record_detail_screen.dart';

/// Planned / non-fault work logging (service, overhaul, inspection).
class FleetLogOtherWorkScreen extends ConsumerStatefulWidget {
  final String? preSelectedAssetId;
  final String? preSelectedWorkTypeLabel;
  final bool embedded;

  const FleetLogOtherWorkScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedWorkTypeLabel,
    this.embedded = false,
  });

  @override
  ConsumerState<FleetLogOtherWorkScreen> createState() =>
      _FleetLogOtherWorkScreenState();
}

class _FleetLogOtherWorkScreenState
    extends ConsumerState<FleetLogOtherWorkScreen> {
  final _service = FleetService();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _labourHoursCtrl = TextEditingController();
  final _machineHoursCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetType? _selectedWorkType;
  List<FleetIssue> _otherOpenIssues = [];
  final List<String> _pendingPhotoPaths = [];
  List<String> _linkedIssueIds = [];
  final List<FleetWorkPartRow> _parts = [];
  List<String> _suggestedPartNames = [];
  DateTime _workCarriedOut = DateTime.now();
  bool _saving = false;
  bool _moreExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestedParts();
    if (widget.preSelectedAssetId != null) {
      _service.getAsset(widget.preSelectedAssetId!).then((a) {
        if (a != null && mounted) {
          setState(() => _selectedAsset = a);
          _loadOtherOpenIssues();
        }
      });
    }
    _loadWorkTypes();
  }

  Future<void> _loadWorkTypes() async {
    final types = await _service.watchTypes(kind: 'work_type').first;
    if (!mounted) return;
    FleetType? picked;
    if (widget.preSelectedWorkTypeLabel != null) {
      final label = widget.preSelectedWorkTypeLabel!.toLowerCase();
      picked = types
          .where((t) => t.label.toLowerCase().contains(label))
          .firstOrNull;
    }
    setState(() => _selectedWorkType = picked ?? types.firstOrNull);
  }

  Future<void> _loadOtherOpenIssues() async {
    final asset = _selectedAsset;
    if (asset?.id == null) return;
    final issues = await _service.watchIssues(assetId: asset!.id).first;
    if (!mounted) return;
    setState(() {
      _otherOpenIssues =
          issues.where((i) => i.status.isOpen).toList();
      _linkedIssueIds = _linkedIssueIds
          .where((id) => _otherOpenIssues.any((i) => i.id == id))
          .toList();
    });
  }

  Future<void> _loadSuggestedParts() async {
    final names = await _service.getSuggestedPartNames();
    if (mounted) setState(() => _suggestedPartNames = names);
  }

  void _resetForm() {
    _titleCtrl.clear();
    _descCtrl.clear();
    _labourHoursCtrl.clear();
    _machineHoursCtrl.clear();
    for (final p in _parts) {
      p.nameCtrl.dispose();
      p.qtyCtrl.dispose();
    }
    setState(() {
      _pendingPhotoPaths.clear();
      _linkedIssueIds.clear();
      _parts.clear();
      _workCarriedOut = DateTime.now();
      _moreExpanded = false;
      if (widget.preSelectedAssetId == null) _selectedAsset = null;
    });
    if (widget.preSelectedAssetId != null) {
      _loadOtherOpenIssues();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
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

  Future<void> _save() async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    if (emp == null) return;
    final actor = resolveWriteActor(emp)!;
    if (_selectedAsset == null) {
      _showError('Please pick which machine you worked on.');
      return;
    }
    if (_selectedWorkType == null) {
      _showError('Please pick a job type.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _showError('Please enter a short title for the work.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showError('Please describe what was done.');
      return;
    }
    final machineHours =
        double.tryParse(_machineHoursCtrl.text.replaceAll(',', '.'));
    if (machineHours == null) {
      _showError('Please enter the machine hour-meter reading.');
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

    setState(() => _saving = true);
    try {
      final labourHours = _labourHoursCtrl.text.trim().isEmpty
          ? 0.0
          : double.tryParse(_labourHoursCtrl.text.replaceAll(',', '.')) ?? 0.0;

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

      final result = await _service.createWorkRecordResilient(
        {
          'asset_id': _selectedAsset!.id,
          'asset_name': _selectedAsset!.name,
          'work_type_id': _selectedWorkType!.id,
          'work_type_name': _selectedWorkType!.label,
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'labour_hours': labourHours,
          'machine_hours_reading': machineHours,
          'photos': <String>[],
          'start_date': _workCarriedOut.toIso8601String(),
          'end_date': DateTime.now().toIso8601String(),
          'logged_by_clock_no': actor.clockNo,
          'logged_by_name': emp.name,
          'linked_issue_ids': _linkedIssueIds,
        },
        photoPaths: _pendingPhotoPaths,
        parts: partModels,
        linkedIssueIds: _linkedIssueIds,
        loggedByClockNo: actor.clockNo,
        loggedByName: actor.name,
      );

      if (!mounted) return;
      final settings = ref.read(fleetSettingsProvider).asData?.value ??
          FleetSettings.defaults;
      final mechanicUx = role_utils.isFleetMechanic(currentEmployee, settings) &&
          !role_utils.isFleetAdmin(currentEmployee);

      if (result.queuedOffline) {
        if (!widget.embedded) Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.workNumber != null
                  ? 'Job ${result.workNumber} saved — syncing…'
                  : 'Work saved offline — will sync when connection returns.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        if (widget.embedded) _resetForm();
      } else if (mechanicUx) {
        if (!widget.embedded) Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job saved. See it in History tab.'),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.embedded) _resetForm();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                FleetWorkRecordDetailScreen(workRecordId: result.id),
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
    final settings = ref.watch(fleetSettingsProvider).asData?.value ??
        FleetSettings.defaults;
    final mechanicUx = role_utils.isFleetMechanic(currentEmployee, settings) &&
        !role_utils.isFleetAdmin(currentEmployee);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');
    final now = DateTime.now();
    final workDateIsToday = _workCarriedOut.year == now.year &&
        _workCarriedOut.month == now.month &&
        _workCarriedOut.day == now.day;

    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (mechanicUx) ...[
            const FleetMechanicGuideBanner.logOtherWork(),
            const SizedBox(height: 16),
          ],

          const FleetSectionLabel('Which machine? (forks, grab or BT) *'),
          FleetAssetSelector(
            value: _selectedAsset,
            onChanged: (asset) {
              setState(() => _selectedAsset = asset);
              _loadOtherOpenIssues();
            },
          ),
          const SizedBox(height: 16),

          const FleetSectionLabel('Job type *'),
          FleetTypeSelector(
            kind: 'work_type',
            value: _selectedWorkType,
            hintText: 'Pick job type',
            onChanged: (type) => setState(() => _selectedWorkType = type),
          ),
          const SizedBox(height: 16),

          const FleetSectionLabel('What you did (short title) *'),
          TextField(
            controller: _titleCtrl,
            decoration: fleetDropdownDecoration(
              hintText: 'e.g. Routine service, Transmission replacement',
            ),
          ),
          const SizedBox(height: 16),

          const FleetSectionLabel('Details of the work *'),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: fleetDropdownDecoration(
              hintText: 'Describe the work carried out.',
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

          ExpansionTile(
            initiallyExpanded: _moreExpanded,
            onExpansionChanged: (v) => setState(() => _moreExpanded = v),
            title: const Text(
              'More details (optional)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
              if (_otherOpenIssues.isNotEmpty) ...[
                const FleetSectionLabel(
                    'Does this job fix any reported problems?'),
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
                maxPhotos: kFleetMaxPhotos,
              ),
              const SizedBox(height: 16),
            ],
          ),
          SizedBox(height: mechanicUx ? 100 : 80),
        ],
      );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save job'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: FleetAppBar(
        title: mechanicUx ? 'Log other work' : 'Log Work',
        actions: [
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
              child: const Text('Save'),
            ),
        ],
      ),
      bottomNavigationBar: mechanicUx
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save job'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
      body: body,
    );
  }
}