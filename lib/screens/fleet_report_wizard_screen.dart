import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee;
import '../models/fleet_asset.dart';
import '../models/fleet_daily_check.dart';
import '../models/fleet_daily_checklist_config.dart';
import '../models/fleet_issue.dart';
import '../providers/fleet_provider.dart';
import '../services/fleet_service.dart';
import '../theme/app_theme.dart';
import '../utils/fleet_constants.dart';
import '../utils/fleet_work_photo_utils.dart';
import '../widgets/fleet_app_bar.dart';
import '../widgets/fleet_asset_grid.dart';
import '../widgets/fleet_form_fields.dart';
import '../utils/fleet_daily_check_gate.dart';
import '../widgets/fleet_issue_widgets.dart';
import '../widgets/fleet_reporter_widgets.dart';
import '../widgets/fleet_work_form_sections.dart';

const _kLastReportAssetKey = 'fleet_last_report_asset_id';
const _kStepCount = 3;

/// Opens the 3-step fleet report wizard.
Future<void> openFleetReportWizard(
  BuildContext context, {
  bool forceStep1 = false,
  FleetAsset? preSelectedAsset,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FleetReportWizardScreen(
        forceStep1: forceStep1,
        preSelectedAsset: preSelectedAsset,
      ),
    ),
  );
}

/// 3-step report flow: machine → urgency → describe + photos.
class FleetReportWizardScreen extends ConsumerStatefulWidget {
  final FleetAsset? preSelectedAsset;
  final FleetIssueSeverity? preSelectedSeverity;
  final bool forceStep1;

  const FleetReportWizardScreen({
    super.key,
    this.preSelectedAsset,
    this.preSelectedSeverity,
    this.forceStep1 = false,
  });

  @override
  ConsumerState<FleetReportWizardScreen> createState() =>
      _FleetReportWizardScreenState();
}

class _FleetReportWizardScreenState
    extends ConsumerState<FleetReportWizardScreen> {
  final _service = FleetService();
  final _descCtrl = TextEditingController();
  final _pageCtrl = PageController();

  FleetAsset? _selectedAsset;
  FleetIssueSeverity? _severity;
  final List<String> _pendingPhotoPaths = [];
  bool _submitting = false;
  bool _showGuide = true;
  int _step = 0;
  FleetDailyChecklistConfig _checklistConfig =
      FleetDailyChecklistConfig.defaults;

  @override
  void initState() {
    super.initState();
    _selectedAsset =
        widget.preSelectedAsset ?? ref.read(selectedFleetAssetProvider);
    if (widget.preSelectedSeverity != null) {
      _severity = widget.preSelectedSeverity!;
    }
    if (!widget.forceStep1) {
      _restoreLastAsset();
    }
    if (widget.preSelectedAsset != null && !widget.forceStep1) {
      _step = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(1);
        }
      });
    }
    if (widget.preSelectedSeverity != null &&
        widget.preSelectedAsset != null &&
        !widget.forceStep1) {
      _step = 2;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(2);
        }
      });
    }
    _loadGuidePref();
    _loadChecklistState();
  }

  Future<void> _loadChecklistState() async {
    final config = await _service.getDailyChecklistConfig();
    if (mounted) setState(() => _checklistConfig = config);
  }

  void _onAssetSelected(FleetAsset asset) {
    setState(() => _selectedAsset = asset);
    if (_step == 0) _goNext();
  }

  void _onSeveritySelected(FleetIssueSeverity severity) {
    setState(() => _severity = severity);
    if (_step == 1) _goNext();
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
    _pageCtrl.dispose();
    super.dispose();
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

  void _goNext() {
    if (_step >= _kStepCount - 1) return;
    final next = _step + 1;
    setState(() => _step = next);
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    if (_step <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    final prev = _step - 1;
    setState(() => _step = prev);
    _pageCtrl.animateToPage(
      prev,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _submit() async {
    if (!guardPersonaSubmit(context)) return;
    final emp = currentEmployee;
    if (emp == null) return;
    final actor = resolveWriteActor(emp)!;

    if (_selectedAsset == null) {
      _showError('Please pick which machine has the problem.');
      return;
    }
    if (_severity == null) {
      _showError('Please say how urgent the problem is.');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      _showError('Please describe the problem.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final issue = FleetIssue(
        assetId: _selectedAsset!.id!,
        assetName: _selectedAsset!.name,
        description: desc,
        severity: _severity!,
        reportedByClockNo: actor.clockNo,
        reportedByName: actor.name,
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
        final oos = _severity! == FleetIssueSeverity.outOfService;
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
    final isLastStep = _step == _kStepCount - 1;

    return Scaffold(
      appBar: FleetAppBar(
        title: 'Report a Problem',
        actions: [
          if (_step > 0)
            TextButton(
              onPressed: _goBack,
              child: const Text('Back'),
            ),
        ],
      ),
      bottomNavigationBar: isLastStep
          ? SafeArea(
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
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: List.generate(_kStepCount, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < _kStepCount - 1 ? 6 : 0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: active
                            ? kBrandOrange
                            : colors.textMuted.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Step ${_step + 1} of $_kStepCount',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                ListView(
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
                    const FleetSectionLabel('Which machine? *'),
                    StreamBuilder<List<FleetDailyCheck>>(
                      stream: _service.watchDailyChecksForDate(),
                      builder: (context, checkSnap) {
                        final checks = checkSnap.data ?? [];
                        final checkByAsset = {
                          for (final c in checks) c.assetId: c,
                        };
                        final settings =
                            ref.watch(fleetSettingsProvider).valueOrNull;
                        return FleetAssetGrid(
                          selectedAsset: _selectedAsset,
                          reporterDepartment: currentEmployee?.department,
                          onAssetSelected: _onAssetSelected,
                          checkBadgeFor: (asset) {
                            if (!_checklistConfig.enabled ||
                                settings == null ||
                                asset.id == null) {
                              return FleetCheckBadge.none;
                            }
                            return fleetCheckBadgeForAsset(
                              asset: asset,
                              todayCheck: checkByAsset[asset.id],
                              checklistConfig: _checklistConfig,
                              settings: settings,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_selectedAsset != null) ...[
                      Text(
                        _selectedAsset!.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const FleetSectionLabel('How urgent is it? *'),
                    Text(
                      'Tap the level that fits — you\'ll go straight to the description.',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: FleetIssueSeverity.values.map((s) {
                        final isSelected = _severity == s;
                        final chipColor =
                            s == FleetIssueSeverity.outOfService
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
                          onSelected: (_) => _onSeveritySelected(s),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const FleetReporterSeverityOptionsGuide(),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_selectedAsset != null) ...[
                      Text(
                        _selectedAsset!.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_severity != null)
                        Text(
                          reporterSeverityLabel(_severity!),
                          style: TextStyle(
                            fontSize: 13,
                            color: fleetSeverityColor(_severity!),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    const FleetSectionLabel('What\'s wrong? *'),
                    Text(
                      'What happened, what you heard or saw, and whether the machine is safe to use.',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 4,
                      autofocus: true,
                      decoration: fleetDropdownDecoration(
                        hintText:
                            'e.g. Loud grinding from mast when lifting pallets',
                      ),
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
                    const SizedBox(height: 80),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}