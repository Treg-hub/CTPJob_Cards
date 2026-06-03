import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_type.dart';
import '../models/fleet_work_part.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import 'fleet_report_issue_screen.dart' show FleetAssetPickerScreen;
import 'fleet_work_record_detail_screen.dart';

/// Mechanic (and admin) work logging screen.
/// Optionally pre-populated with an asset and/or linked issue.
class FleetLogWorkScreen extends ConsumerStatefulWidget {
  final String? preSelectedAssetId;
  final String? preSelectedAssetName;
  final String? linkedIssueId;

  const FleetLogWorkScreen({
    super.key,
    this.preSelectedAssetId,
    this.preSelectedAssetName,
    this.linkedIssueId,
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
  List<FleetType> _workTypes = [];
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final List<String> _photoUrls = [];
  List<String> _linkedIssueIds = [];
  bool _saving = false;

  // In-progress parts
  final List<_PartRow> _parts = [];

  @override
  void initState() {
    super.initState();
    _loadWorkTypes();
    if (widget.preSelectedAssetId != null) {
      _service.getAsset(widget.preSelectedAssetId!).then((a) {
        if (a != null && mounted) setState(() => _selectedAsset = a);
      });
    }
    if (widget.linkedIssueId != null) {
      _linkedIssueIds = [widget.linkedIssueId!];
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

  Future<void> _loadWorkTypes() async {
    final types = await _service.watchTypes(kind: 'work_type').first;
    if (mounted) {
      setState(() {
        _workTypes = types;
        _selectedWorkType = types.firstOrNull;
      });
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _addPhoto() async {
    if (_photoUrls.length >= 5) return;
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

    try {
      final url = await _service.uploadFleetPhoto(
        localPath: localPath,
        fleetRef: 'fleet_work_records/_temp',
      );
      if (mounted) setState(() => _photoUrls.add(url));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo upload failed.')),
        );
      }
    }
  }

  Future<void> _save() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (_selectedAsset == null) {
      _showError('Please select an asset.');
      return;
    }
    if (_selectedWorkType == null) {
      _showError('Please select a work type.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _showError('Please enter a title.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showError('Please enter a description.');
      return;
    }
    final labourHours = double.tryParse(_labourHoursCtrl.text);
    if (labourHours == null || labourHours <= 0) {
      _showError('Please enter valid labour hours (e.g. 2.5).');
      return;
    }
    if (_parts.any((p) => p.nameCtrl.text.trim().isEmpty)) {
      _showError('All part rows must have a part name.');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'asset_id': _selectedAsset!.id,
        'asset_name': _selectedAsset!.name,
        'work_type_id': _selectedWorkType!.id,
        'work_type_name': _selectedWorkType!.label,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'labour_hours': labourHours,
        if (_machineHoursCtrl.text.trim().isNotEmpty)
          'machine_hours_reading':
              double.tryParse(_machineHoursCtrl.text),
        'photos': _photoUrls,
        'start_date': _startDate.toIso8601String(),
        'end_date': _endDate.toIso8601String(),
        'logged_by_clock_no': emp.clockNo,
        'logged_by_name': emp.name,
        'linked_issue_ids': _linkedIssueIds,
      };

      final result = await _service.createWorkRecord(data);
      final recordId = result['id'] as String;

      // Save parts as sub-collection
      for (final row in _parts) {
        final name = row.nameCtrl.text.trim();
        if (name.isEmpty) continue;
        final qty = int.tryParse(row.qtyCtrl.text.trim());
        await _service.addPart(
            recordId, FleetWorkPart(partName: name, quantity: qty));
      }

      // Resolve linked issues
      for (final issueId in _linkedIssueIds) {
        await _service.resolveIssueWithWorkRecord(
            issueId, recordId, emp.clockNo, emp.name);
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) =>
                  FleetWorkRecordDetailScreen(workRecordId: recordId)),
        );
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

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Work'),
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _save,
              child:
                  const Text('Save', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Asset ──────────────────────────────────────────────────────
          _Label('Asset *'),
          if (widget.preSelectedAssetId != null && _selectedAsset != null)
            // Pre-selected from issue — not editable
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.forklift, color: kBrandOrange),
                  const SizedBox(width: 12),
                  Text(_selectedAsset!.name,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else
            InkWell(
              onTap: () async {
                final asset =
                    await Navigator.of(context).push<FleetAsset>(
                  MaterialPageRoute(
                      builder: (_) => const FleetAssetPickerScreen()),
                );
                if (asset != null) setState(() => _selectedAsset = asset);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.forklift,
                        color: _selectedAsset != null
                            ? kBrandOrange
                            : Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _selectedAsset == null
                          ? Text('Tap to select asset',
                              style:
                                  TextStyle(color: Colors.grey[600]))
                          : Text(_selectedAsset!.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // ── Work type ─────────────────────────────────────────────────
          _Label('Work Type *'),
          DropdownButtonFormField<FleetType>(
            key: ValueKey(_selectedWorkType?.id),
            initialValue: _selectedWorkType,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: _workTypes
                .map((t) =>
                    DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) => setState(() => _selectedWorkType = v),
          ),
          const SizedBox(height: 16),

          // ── Title ─────────────────────────────────────────────────────
          _Label('Title *'),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                hintText: 'e.g. Engine oil change + filter',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),

          // ── Description ───────────────────────────────────────────────
          _Label('Description *'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'Describe what was done.',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),

          // ── Hours ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Labour Hours *'),
                    TextField(
                      controller: _labourHoursCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          hintText: '2.5',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Machine Hours Reading'),
                    TextField(
                      controller: _machineHoursCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          hintText: 'optional',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Dates ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: 'Start Date',
                  date: _startDate,
                  fmt: fmt,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateButton(
                  label: 'End Date',
                  date: _endDate,
                  fmt: fmt,
                  onTap: () => _pickDate(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Linked issues ─────────────────────────────────────────────
          if (_linkedIssueIds.isNotEmpty) ...[
            _Label('Linked Issues'),
            Wrap(
              spacing: 8,
              children: _linkedIssueIds
                  .map((id) => Chip(
                        label: Text(id.substring(0, 8),
                            style: const TextStyle(fontSize: 11)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // ── Parts ─────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Label('Parts Used'),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Part'),
                onPressed: () {
                  setState(() => _parts.add(_PartRow()));
                },
              ),
            ],
          ),
          ..._parts.asMap().entries.map((entry) {
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
                      decoration: const InputDecoration(
                          hintText: 'Part name',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          hintText: 'Qty',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        row.nameCtrl.dispose();
                        row.qtyCtrl.dispose();
                        _parts.removeAt(i);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),

          // ── Photos ────────────────────────────────────────────────────
          _Label('Photos (optional, max 5)'),
          Wrap(
            spacing: 8,
            children: [
              ..._photoUrls.map((url) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _photoUrls.remove(url)),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  )),
              if (_photoUrls.length < 5)
                GestureDetector(
                  onTap: _addPhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_a_photo,
                        color: Colors.grey),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _PartRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton(
      {required this.label,
      required this.date,
      required this.fmt,
      required this.onTap});
  final String label;
  final DateTime date;
  final DateFormat fmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(fmt.format(date),
                    style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
