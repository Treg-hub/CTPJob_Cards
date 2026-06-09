import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../models/fleet_settings.dart';
import '../models/fleet_type.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_selector.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_reporter_widgets.dart';

/// Reporters, mechanics, and admins can report a problem on a forklift or grab.
class FleetReportIssueScreen extends ConsumerStatefulWidget {
  final FleetAsset? preSelectedAsset;

  const FleetReportIssueScreen({super.key, this.preSelectedAsset});

  @override
  ConsumerState<FleetReportIssueScreen> createState() =>
      _FleetReportIssueScreenState();
}

class _FleetReportIssueScreenState
    extends ConsumerState<FleetReportIssueScreen> {
  final _service = FleetService();
  final _descCtrl = TextEditingController();
  final _partCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetIssueSeverity _severity = FleetIssueSeverity.medium;
  final List<String> _selectedParts = [];
  final List<String> _pendingPhotoPaths = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedAsset =
        widget.preSelectedAsset ?? ref.read(selectedFleetAssetProvider);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _partCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_pendingPhotoPaths.length >= 3) return;
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

  void _togglePart(String part) {
    setState(() {
      if (_selectedParts.contains(part)) {
        _selectedParts.remove(part);
      } else {
        _selectedParts.add(part);
      }
    });
  }

  Future<void> _addCustomPart() async {
    final part = _partCtrl.text.trim();
    if (part.isEmpty) return;
    if (_selectedParts.any((p) => p.toLowerCase() == part.toLowerCase())) {
      _partCtrl.clear();
      return;
    }
    setState(() => _selectedParts.add(part));
    _partCtrl.clear();
    try {
      await _service.ensureIssuePartType(part);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (_selectedAsset == null) {
      _showError('Please pick which Hyster has the problem.');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.length < 10) {
      _showError('Please describe the problem (at least 10 characters).');
      return;
    }
    if (_selectedParts.isEmpty) {
      _showError('Please pick or type at least one affected part.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final issue = FleetIssue(
        assetId: _selectedAsset!.id!,
        assetName: _selectedAsset!.name,
        description: desc,
        severity: _severity,
        reportedByClockNo: emp.clockNo,
        reportedByName: emp.name,
        parts: List.from(_selectedParts),
        photos: const [],
      );
      final result = await _service.createIssueResilient(
        issue,
        photoPaths: _pendingPhotoPaths,
      );
      if (mounted) {
        final oos = _severity == FleetIssueSeverity.outOfService;
        final queued = result.queuedOffline;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? 'Report saved offline — will sync when connection returns.'
                  : oos
                      ? 'Report sent. Mechanic notified — machine marked out of service.'
                      : 'Report sent. The mechanic will see it under To Fix.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final primary = theme.colorScheme.primary;

    final settingsAsync = ref.watch(fleetSettingsProvider);
    final settings = settingsAsync.asData?.value ?? FleetSettings.defaults;
    final emp = currentEmployee;
    final reporterUx = role_utils.isFleetReporter(emp, settings) &&
        !role_utils.isFleetAdmin(emp);

    return Scaffold(
      appBar: FleetAppBar(
        title: reporterUx ? 'Report a Problem' : 'Report an Issue',
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_submitting ? 'Sending…' : 'Send report'),
            style: FilledButton.styleFrom(
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
          if (reporterUx) ...[
            const FleetReporterGuideBanner(),
            const SizedBox(height: 20),
          ],

          const FleetSectionLabel('Which Hyster? (forks or grab) *'),
          FleetAssetSelector(
            value: _selectedAsset,
            onChanged: (asset) => setState(() => _selectedAsset = asset),
          ),
          const SizedBox(height: 20),

          const FleetSectionLabel('How urgent is it? *'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FleetIssueSeverity.values.map((s) {
              final isSelected = _severity == s;
              final chipColor = s == FleetIssueSeverity.outOfService
                  ? theme.colorScheme.error
                  : primary;
              return ChoiceChip(
                label: Text(reporterSeverityLabel(s)),
                selected: isSelected,
                selectedColor: chipColor,
                labelStyle: TextStyle(
                  color: isSelected
                      ? onColor(chipColor)
                      : colors.chipUnselectedLabel,
                  fontWeight: FontWeight.w500,
                ),
                onSelected: (_) => setState(() => _severity = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          FleetReporterSeverityHint(severity: _severity),
          const SizedBox(height: 20),

          const FleetSectionLabel('What\'s wrong? *'),
          Text(
            'Be specific — what happened, what you heard or saw, and whether the machine is safe to use.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: fleetDropdownDecoration(
              hintText: 'e.g. Loud grinding from mast when lifting pallets',
            ),
          ),
          const SizedBox(height: 20),

          const FleetSectionLabel('Which part is affected? *'),
          Text(
            'Tap a saved part or type a new one below.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<FleetType>>(
            stream: _service.watchTypes(kind: 'issue_part'),
            builder: (context, snapshot) {
              final savedParts =
                  (snapshot.data ?? []).map((t) => t.label).toList();
              if (savedParts.isEmpty) {
                return Text(
                  'No saved parts yet — type the affected part below.',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: savedParts.map((part) {
                  final selected = _selectedParts.contains(part);
                  return FilterChip(
                    label: Text(part),
                    selected: selected,
                    selectedColor: primary.withValues(alpha: 0.2),
                    checkmarkColor: primary,
                    labelStyle: TextStyle(
                      color:
                          selected ? primary : colors.chipUnselectedLabel,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => _togglePart(part),
                  );
                }).toList(),
              );
            },
          ),
          if (_selectedParts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedParts.map((part) {
                return InputChip(
                  label: Text(part),
                  deleteIconColor: primary,
                  onDeleted: () => setState(() => _selectedParts.remove(part)),
                  backgroundColor: primary.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: colors.chipUnselectedLabel,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _partCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addCustomPart(),
                  decoration: fleetDropdownDecoration(
                    hintText: 'e.g. Hydraulic hose, Mast chain',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addCustomPart,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const FleetSectionLabel('Photos (optional, max 3)'),
          Text(
            'A photo helps the mechanic see the problem before they arrive.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          _PhotoRow(
            pendingPaths: _pendingPhotoPaths,
            outlineColor: theme.colorScheme.outline,
            mutedColor: colors.textMuted,
            onAdd: _addPhoto,
            onRemove: (path) =>
                setState(() => _pendingPhotoPaths.remove(path)),
          ),
          const SizedBox(height: 12),
          Text(
            'Report time is saved automatically when you send.',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.pendingPaths,
    required this.outlineColor,
    required this.mutedColor,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> pendingPaths;
  final Color outlineColor;
  final Color mutedColor;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...pendingPaths.map((path) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(path),
                      width: 80, height: 80, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemove(path),
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            )),
        if (pendingPaths.length < 3)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: outlineColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.add_a_photo, color: mutedColor),
            ),
          ),
      ],
    );
  }
}