import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_grid.dart';
import '../widgets/fleet_form_fields.dart';
import '../widgets/fleet_reporter_widgets.dart';

const _kLastReportAssetKey = 'fleet_last_report_asset_id';

/// Opens the single-page fleet report wizard (machine → urgency → describe).
Future<void> openFleetReportWizard(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const FleetReportWizardScreen()),
  );
}

/// Single-screen report flow for reporter departments.
class FleetReportWizardScreen extends ConsumerStatefulWidget {
  final FleetAsset? preSelectedAsset;
  final FleetIssueSeverity? preSelectedSeverity;

  const FleetReportWizardScreen({
    super.key,
    this.preSelectedAsset,
    this.preSelectedSeverity,
  });

  @override
  ConsumerState<FleetReportWizardScreen> createState() =>
      _FleetReportWizardScreenState();
}

class _FleetReportWizardScreenState
    extends ConsumerState<FleetReportWizardScreen> {
  final _service = FleetService();
  final _descCtrl = TextEditingController();

  FleetAsset? _selectedAsset;
  FleetIssueSeverity _severity = FleetIssueSeverity.medium;
  final List<String> _pendingPhotoPaths = [];
  bool _submitting = false;
  bool _showGuide = true;

  @override
  void initState() {
    super.initState();
    _selectedAsset =
        widget.preSelectedAsset ?? ref.read(selectedFleetAssetProvider);
    if (widget.preSelectedSeverity != null) {
      _severity = widget.preSelectedSeverity!;
    }
    _restoreLastAsset();
    _loadGuidePref();
  }

  Future<void> _restoreLastAsset() async {
    if (_selectedAsset != null) return;
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString(_kLastReportAssetKey);
    if (lastId == null) return;
    final asset = await _service.getAsset(lastId);
    if (asset != null && mounted) {
      setState(() => _selectedAsset = asset);
    }
  }

  Future<void> _loadGuidePref() async {
    final prefs = await SharedPreferences.getInstance();
    final emp = currentEmployee;
    if (emp == null) return;
    final dismissed =
        prefs.getBool('fleet_reporter_guide_dismissed_${emp.clockNo}') ?? false;
    if (mounted) setState(() => _showGuide = !dismissed);
  }

  Future<void> _dismissGuide() async {
    final emp = currentEmployee;
    if (emp != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
          'fleet_reporter_guide_dismissed_${emp.clockNo}', true);
    }
    if (mounted) setState(() => _showGuide = false);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_pendingPhotoPaths.isNotEmpty) return;
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

  Future<void> _submit() async {
    final emp = currentEmployee;
    if (emp == null) return;

    if (_selectedAsset == null) {
      _showError('Please pick which machine has the problem.');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.length < 10) {
      _showError('Please describe the problem (at least 10 characters).');
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
        parts: const [],
        photos: const [],
      );
      final result = await _service.createIssueResilient(
        issue,
        photoPaths: _pendingPhotoPaths,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastReportAssetKey, _selectedAsset!.id!);
      await _dismissGuide();

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

    return Scaffold(
      appBar: const FleetAppBar(title: 'Report a Problem'),
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
          if (_showGuide) ...[
            const FleetReporterGuideBanner(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _dismissGuide,
                child: const Text('Got it — hide tip'),
              ),
            ),
            const SizedBox(height: 8),
          ],

          const FleetSectionLabel('1. Which machine? *'),
          FleetAssetGrid(
            selectedAsset: _selectedAsset,
            onAssetSelected: (asset) => setState(() => _selectedAsset = asset),
          ),
          const SizedBox(height: 20),

          const FleetSectionLabel('2. How urgent is it? *'),
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
          const SizedBox(height: 8),
          FleetReporterSeverityHint(severity: _severity),
          const SizedBox(height: 20),

          const FleetSectionLabel('3. What\'s wrong? *'),
          Text(
            'What happened, what you heard or saw, and whether the machine is safe to use.',
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
          const SizedBox(height: 16),

          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pendingPhotoPaths.isEmpty ? _addPhoto : null,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(
                  _pendingPhotoPaths.isEmpty
                      ? 'Add photo (optional)'
                      : 'Photo added',
                ),
              ),
              if (_pendingPhotoPaths.isNotEmpty) ...[
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_pendingPhotoPaths.first),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      setState(() => _pendingPhotoPaths.clear()),
                ),
              ],
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}