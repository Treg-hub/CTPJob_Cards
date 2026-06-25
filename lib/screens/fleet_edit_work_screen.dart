import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
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
import '../widgets/fleet_type_selector.dart';
import '../widgets/fleet_work_form_sections.dart';

/// Edit an existing work record within the 7-day window (admin exempt on Pulse only).
class FleetEditWorkScreen extends ConsumerStatefulWidget {
  final String workRecordId;

  const FleetEditWorkScreen({super.key, required this.workRecordId});

  @override
  ConsumerState<FleetEditWorkScreen> createState() =>
      _FleetEditWorkScreenState();
}

class _FleetEditWorkScreenState extends ConsumerState<FleetEditWorkScreen> {
  final _service = FleetService();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _labourHoursCtrl = TextEditingController();
  final _machineHoursCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetType? _selectedWorkType;
  final List<String> _savedPhotoUrls = [];
  final List<String> _pendingPhotoPaths = [];
  List<String> _linkedIssueIds = [];
  final List<FleetWorkPartRow> _parts = [];
  List<String> _suggestedPartNames = [];
  DateTime _workCarriedOut = DateTime.now();
  DateTime? _loadedEndDate;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestedParts();
    _loadExistingRecord(widget.workRecordId);
  }

  Future<void> _loadExistingRecord(String id) async {
    try {
      final record = await _service.getWorkRecord(id);
      if (record == null) return;

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
                record.hasLinkedCosts
                    ? 'This job is locked because costs have been linked.'
                    : 'This job is locked — jobs can be edited for '
                        '${FleetWorkRecord.editLockDays} days.',
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
        _savedPhotoUrls.addAll(record.photos);
        _linkedIssueIds = List.from(record.linkedIssueIds);
        _parts.addAll(parts.map((p) {
          final row = FleetWorkPartRow();
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

  Future<void> _loadSuggestedParts() async {
    final names = await _service.getSuggestedPartNames();
    if (mounted) setState(() => _suggestedPartNames = names);
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
    final path = await _service.pickAndCompressPhoto(source);
    if (path != null && mounted) setState(() => _pendingPhotoPaths.add(path));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (_selectedAsset == null || _selectedWorkType == null) {
      _showError('Please complete all required fields.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty) {
      _showError('Title and description are required.');
      return;
    }
    final machineHours =
        double.tryParse(_machineHoursCtrl.text.replaceAll(',', '.'));
    if (machineHours == null) {
      _showError('Please enter the machine hour-meter reading.');
      return;
    }

    setState(() => _saving = true);
    try {
      final fresh = await _service.getWorkRecord(widget.workRecordId);
      final settings = await _service.getSettings();
      final canEdit = fresh?.canEdit(
            isMechanic: role_utils.isFleetMechanic(currentEmployee, settings),
            isAdmin: role_utils.isFleetAdmin(currentEmployee),
          ) ??
          false;
      if (fresh == null || !canEdit) {
        _showError('This job can no longer be edited.');
        return;
      }

      final labourHours = double.tryParse(
              _labourHoursCtrl.text.replaceAll(',', '.')) ??
          0.0;
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

      final uploaded =
          await _service.uploadPhotosForRecord(widget.workRecordId, _pendingPhotoPaths);
      final allPhotos = [..._savedPhotoUrls, ...uploaded];

      await _service.updateWorkRecord(widget.workRecordId, {
        'asset_id': _selectedAsset!.id,
        'asset_name': _selectedAsset!.name,
        'work_type_id': _selectedWorkType!.id,
        'work_type_name': _selectedWorkType!.label,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'labour_hours': labourHours,
        'machine_hours_reading': machineHours,
        'photos': allPhotos,
        'start_date': Timestamp.fromDate(_workCarriedOut),
        'end_date': Timestamp.fromDate(_loadedEndDate ?? DateTime.now()),
        'linked_issue_ids': _linkedIssueIds,
      });
      await _service.replaceParts(widget.workRecordId, partModels);

      if (mounted) Navigator.of(context).pop();
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

    if (_loading) {
      return Scaffold(
        appBar: FleetAppBar(
            title: mechanicUx ? 'Edit job' : 'Edit Work'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: FleetAppBar(
        title: mechanicUx ? 'Edit job' : 'Edit Work',
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
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FleetWorkDatesCard(
            workCarriedOut: _workCarriedOut,
            dateFmt: dateFmt,
            workDateIsToday: workDateIsToday,
            onEdit: _pickWorkDate,
          ),
          const SizedBox(height: 16),
          const FleetSectionLabel('Asset *'),
          FleetAssetSelector(
            value: _selectedAsset,
            onChanged: (asset) => setState(() => _selectedAsset = asset),
          ),
          const SizedBox(height: 16),
          const FleetSectionLabel('Work Type *'),
          FleetTypeSelector(
            kind: 'work_type',
            value: _selectedWorkType,
            onChanged: (type) => setState(() => _selectedWorkType = type),
          ),
          const SizedBox(height: 16),
          const FleetSectionLabel('Title *'),
          TextField(
            controller: _titleCtrl,
            decoration: fleetDropdownDecoration(hintText: 'Work title'),
          ),
          const SizedBox(height: 16),
          const FleetSectionLabel('Description *'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: fleetDropdownDecoration(hintText: 'Describe what was done'),
          ),
          const SizedBox(height: 16),
          const FleetSectionLabel('Machine hour-meter reading *'),
          TextField(
            controller: _machineHoursCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          const FleetSectionLabel('Labour hours (optional)'),
          TextField(
            controller: _labourHoursCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          FleetWorkPartsSection(
            parts: _parts,
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
            savedPhotoUrls: _savedPhotoUrls,
            pendingPhotoPaths: _pendingPhotoPaths,
            onAddPhoto: _addPhoto,
            onRemoveSaved: (url) => setState(() => _savedPhotoUrls.remove(url)),
            onRemovePending: (path) =>
                setState(() => _pendingPhotoPaths.remove(path)),
          ),
          const SizedBox(height: 16),
          if (_saving)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save changes'),
            ),
        ],
      ),
    );
  }
}