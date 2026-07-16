import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/persona_audit.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

import '../stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/employee_roster_cache.dart';
import '../services/firestore_service.dart';
import '../models/employee.dart';
import 'admin_modules_screen.dart';
import 'admin_tools_screen.dart';
import 'geofence_editor_screen.dart';
import '../services/device_health_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../utils/update_channels.dart';

// ---------------------------------------------------------------------------
// AdminScreen
// ---------------------------------------------------------------------------

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  // ── Employees ──────────────────────────────────────────────────────────────
  final TextEditingController _employeeSearchController = TextEditingController();
  List<Employee> _allEmployees = [];

  // ── Structures ─────────────────────────────────────────────────────────────
  final TextEditingController deptController = TextEditingController();
  final TextEditingController areaController = TextEditingController();
  final TextEditingController machineController = TextEditingController();
  final TextEditingController structureSearchController = TextEditingController();
  String? selectedDeptForArea;
  String? selectedDeptForMachine;
  String? selectedAreaForMachine;
  Map<String, dynamic> _structure = {};

  // ── Settings — kill-switch + channel publish (settings/app) ────────────────
  final TextEditingController _minBuildController = TextEditingController();
  final TextEditingController _updateUrlController = TextEditingController();
  // Default channel
  final TextEditingController _pubVersionController = TextEditingController();
  final TextEditingController _pubBuildController = TextEditingController();
  final TextEditingController _pubNotesController = TextEditingController();
  final TextEditingController _pubShaController = TextEditingController();
  bool _pubForceUpdate = false;
  bool _defaultEnabled = true;
  // Ink channel
  bool _inkEnabled = false;
  bool _inkForce = false;
  final TextEditingController _inkVersionController = TextEditingController();
  final TextEditingController _inkBuildController = TextEditingController();
  final TextEditingController _inkNotesController = TextEditingController();
  final TextEditingController _inkUrlController = TextEditingController();
  final TextEditingController _inkShaController = TextEditingController();
  /// Department / people targets for the "departments" channel (id: ink).
  Set<String> _inkDepartments = {};
  Set<String> _inkClockNos = {};
  // People / pilot channel (id: testers) — highest match priority
  bool _testersEnabled = false;
  bool _testersForce = false;
  final TextEditingController _testersVersionController = TextEditingController();
  final TextEditingController _testersBuildController = TextEditingController();
  final TextEditingController _testersNotesController = TextEditingController();
  final TextEditingController _testersUrlController = TextEditingController();
  final TextEditingController _testersShaController = TextEditingController();
  Set<String> _testerDepartments = {};
  Set<String> _testerClockNos = {};
  bool _killSwitchLoading = true;
  String? _thisDeviceBuildLabel;
  String? _thisDeviceVersion;
  String? _thisDeviceBuild;
  String? _currentClockNo;

  // ── Settings — escalation config ──────────────────────────────────────────
  final TextEditingController _stage1MinController = TextEditingController(text: '5');
  final TextEditingController _stage2MinController = TextEditingController(text: '10');
  final TextEditingController _stage3MinController = TextEditingController(text: '30');
  final TextEditingController _stage4MinController = TextEditingController(text: '60');
  bool _stage1Enabled = true;
  bool _stage2Enabled = true;
  bool _stage3Enabled = false;
  bool _stage4Enabled = false;
  bool _stage1LoadedEnabled = true;
  bool _stage2LoadedEnabled = true;
  bool _stage3LoadedEnabled = false;
  bool _stage4LoadedEnabled = false;
  DateTime? _stage1LoadedEnabledAt;
  DateTime? _stage2LoadedEnabledAt;
  DateTime? _stage3LoadedEnabledAt;
  DateTime? _stage4LoadedEnabledAt;

  static const _allRules = [
    'operator', 'onsite_managers', 'foremen', 'onsite_dept_managers',
    'onsite_workshop_manager', 'onsite_mechanics', 'onsite_electricians',
    'offsite_managers', 'offsite_dept_managers', 'offsite_workshop_manager',
  ];
  static const _ruleLabels = {
    'operator': 'Job Creator (Operator)',
    'onsite_managers': 'On-site Mech/Elec Manager',
    'foremen': 'On-site Foreman / Shift Leader',
    'onsite_dept_managers': 'On-site Department Manager',
    'onsite_workshop_manager': 'On-site Workshop Manager',
    'onsite_mechanics': 'On-site Mechanics',
    'onsite_electricians': 'On-site Electricians',
    'offsite_managers': 'Off-site Mech/Elec Manager',
    'offsite_dept_managers': 'Off-site Department Manager',
    'offsite_workshop_manager': 'Off-site Workshop Manager',
  };
  Set<String> _stage1Recipients = {'onsite_managers', 'foremen'};
  Set<String> _stage2Recipients = {'onsite_dept_managers', 'onsite_workshop_manager'};
  Set<String> _stage3Recipients = {};
  Set<String> _stage4Recipients = {};

  // ── Employees ─────────────────────────────────────────────────────────────
  final Set<String> _selectedClockNos = {};
  bool _employeesLoaded = false;

  // ── Comms tab ─────────────────────────────────────────────────────────────
  final TextEditingController _broadcastTitleController = TextEditingController(
    text: 'Update required — CTP Job Cards',
  );
  final TextEditingController _broadcastBodyController = TextEditingController(
    text: 'A required app update is available. Open the app and tap Update Now to install it.',
  );
  bool _isBroadcasting = false;
  Map<String, dynamic>? _lastBroadcastResult;
  final TextEditingController _targetedClockNosController =
      TextEditingController();
  bool _isTargetedBroadcasting = false;
  Map<String, dynamic>? _lastTargetedBroadcastResult;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 0);
    _tabController.addListener(_onTabChanged);
    _loadStructure();
    _loadKillSwitch();
    _loadNotificationConfig();
    _loadCurrentClockNo();
  }

  void _onTabChanged() {
    setState(() {});
    if ((_tabController.index == 1 || _tabController.index == 4) &&
        !_employeesLoaded) {
      _employeesLoaded = true;
      _loadEmployees();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _employeeSearchController.dispose();
    deptController.dispose();
    areaController.dispose();
    machineController.dispose();
    structureSearchController.dispose();
    _minBuildController.dispose();
    _updateUrlController.dispose();
    _pubVersionController.dispose();
    _pubBuildController.dispose();
    _pubNotesController.dispose();
    _pubShaController.dispose();
    _inkVersionController.dispose();
    _inkBuildController.dispose();
    _inkNotesController.dispose();
    _inkUrlController.dispose();
    _inkShaController.dispose();
    _testersVersionController.dispose();
    _testersBuildController.dispose();
    _testersNotesController.dispose();
    _testersUrlController.dispose();
    _testersShaController.dispose();
    _stage1MinController.dispose();
    _stage2MinController.dispose();
    _stage3MinController.dispose();
    _stage4MinController.dispose();
    _broadcastTitleController.dispose();
    _broadcastBodyController.dispose();
    _targetedClockNosController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    if (mounted) setState(() {});
  }

  Future<void> _loadEmployees({bool force = false}) async {
    try {
      _allEmployees = force
          ? await EmployeeRosterCache.instance.reload()
          : await EmployeeRosterCache.instance.getRoster();
      if (mounted) setState(() {});
    } catch (e) {
      _showError('Error loading employees: $e');
    }
  }

  /// Pure search filter — safe to call during build (no setState).
  List<Employee> get _displayedEmployees {
    final q = _employeeSearchController.text.toLowerCase();
    if (q.isEmpty) return _allEmployees;
    return _allEmployees.where((e) =>
      e.name.toLowerCase().contains(q) ||
      e.department.toLowerCase().contains(q) ||
      e.position.toLowerCase().contains(q) ||
      e.clockNo.toLowerCase().contains(q),
    ).toList();
  }

  Future<void> _loadStructure() async {
    try {
      _structure = _normalizeStructure(await _firestoreService.getFactoryStructure());
      if (mounted) setState(() {});
    } catch (e) {
      _showError('Error loading structure: $e');
    }
  }

  Map<String, dynamic> _normalizeStructure(Map<String, dynamic> structure) {
    final out = <String, dynamic>{};
    structure.forEach((dept, areas) {
      if (areas is Map) {
        final normAreas = <String, dynamic>{};
        (areas as Map<String, dynamic>).forEach((area, machines) {
          normAreas[area] = machines is List ? machines : (machines is String ? [machines] : []);
        });
        out[dept] = normAreas;
      } else {
        out[dept] = {};
      }
    });
    return out;
  }

  Future<void> _loadKillSwitch() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('app').get();
      final data = doc.data() ?? {};
      String? deviceLabel;
      String? deviceVersion;
      String? deviceBuild;
      try {
        final info = await PackageInfo.fromPlatform();
        deviceVersion = info.version;
        deviceBuild = info.buildNumber;
        deviceLabel = 'v${info.version} (build ${info.buildNumber})';
      } catch (_) {}
      final channels = channelsFromSettingsApp(data);
      UpdateChannel ch(String id) =>
          channels.firstWhere((c) => c.id == id, orElse: () => UpdateChannel(id: id));
      final def = ch('default');
      final ink = ch('ink');
      final testers = ch('testers');
      if (!mounted) return;
      setState(() {
        _minBuildController.text = (data['minSupportedBuild'] ?? '').toString();
        _updateUrlController.text = (data['updateDownloadUrl'] ?? '').toString();
        _defaultEnabled = def.enabled;
        _pubVersionController.text = def.latestVersion;
        _pubBuildController.text = def.latestBuild;
        _pubNotesController.text = def.releaseNotes;
        _pubShaController.text = def.apkSha256;
        _pubForceUpdate = def.forceUpdate;
        _inkEnabled = ink.enabled &&
            (ink.hasPublishMetadata || ink.match.departments.isNotEmpty);
        _inkForce = ink.forceUpdate;
        _inkVersionController.text = ink.latestVersion;
        _inkBuildController.text = ink.latestBuild;
        _inkNotesController.text = ink.releaseNotes;
        _inkUrlController.text = ink.downloadUrl;
        _inkShaController.text = ink.apkSha256;
        _inkDepartments = ink.match.departments.toSet();
        if (_inkDepartments.isEmpty &&
            (ink.hasPublishMetadata || ink.enabled)) {
          // Sensible default for first-time ink channel setup
          _inkDepartments = {'Ink Factory'};
        }
        _inkClockNos = ink.match.clockNos.toSet();
        _testersEnabled = testers.enabled &&
            (testers.hasPublishMetadata ||
                testers.match.clockNos.isNotEmpty ||
                testers.match.departments.isNotEmpty);
        _testersForce = testers.forceUpdate;
        _testersVersionController.text = testers.latestVersion;
        _testersBuildController.text = testers.latestBuild;
        _testersNotesController.text = testers.releaseNotes;
        _testersUrlController.text = testers.downloadUrl;
        _testersShaController.text = testers.apkSha256;
        _testerClockNos = testers.match.clockNos.toSet();
        _testerDepartments = testers.match.departments.toSet();
        _thisDeviceBuildLabel = deviceLabel;
        _thisDeviceVersion = deviceVersion;
        _thisDeviceBuild = deviceBuild;
        _killSwitchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _killSwitchLoading = false);
    }
  }

  void _fillPublishFromThisDevice() {
    setState(() {
      if (_thisDeviceVersion != null) {
        _pubVersionController.text = _thisDeviceVersion!;
      }
      if (_thisDeviceBuild != null) {
        _pubBuildController.text = _thisDeviceBuild!;
      }
    });
  }

  void _fillInkFromThisDevice() {
    setState(() {
      if (_thisDeviceVersion != null) {
        _inkVersionController.text = _thisDeviceVersion!;
      }
      if (_thisDeviceBuild != null) {
        _inkBuildController.text = _thisDeviceBuild!;
      }
    });
  }

  void _fillTestersFromThisDevice() {
    setState(() {
      if (_thisDeviceVersion != null) {
        _testersVersionController.text = _thisDeviceVersion!;
      }
      if (_thisDeviceBuild != null) {
        _testersBuildController.text = _thisDeviceBuild!;
      }
    });
  }

  /// Departments from live employees + factory structure keys.
  List<String> get _departmentOptions {
    final s = <String>{};
    for (final e in _allEmployees) {
      final d = e.department.trim();
      if (d.isNotEmpty) s.add(d);
    }
    for (final k in _structure.keys) {
      final d = k.toString().trim();
      if (d.isNotEmpty) s.add(d);
    }
    final list = s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<Employee> get _employeesSorted {
    final list = List<Employee>.from(_allEmployees);
    list.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.clockNo.compareTo(b.clockNo);
    });
    return list;
  }

  /// Chip labels for selected clocks: "Name (22)".
  List<String> _employeeChipLabels(Set<String> clocks) {
    final byClock = {for (final e in _allEmployees) e.clockNo: e};
    final labels = <String>[];
    final sorted = clocks.toList()..sort();
    for (final c in sorted) {
      final e = byClock[c];
      if (e == null || e.name.trim().isEmpty) {
        labels.add(c);
      } else {
        labels.add('${e.name.trim()} ($c)');
      }
    }
    return labels;
  }

  Future<void> _pickDepartments({
    required Set<String> selected,
    required void Function(Set<String>) onSave,
  }) async {
    if (_departmentOptions.isEmpty && _allEmployees.isEmpty) {
      await _loadEmployees();
      await _loadStructure();
    }
    if (!mounted) return;
    final options = _departmentOptions;
    if (options.isEmpty) {
      _showError('No departments found. Load employees or factory structure first.');
      return;
    }
    final draft = Set<String>.from(selected);
    final filterCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = filterCtrl.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? options
              : options.where((d) => d.toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: const Text('Select departments'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: filterCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Filter departments…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${draft.length} selected',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).appColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final d = filtered[i];
                        final on = draft.contains(d);
                        final count = _allEmployees
                            .where((e) => e.department.trim() == d)
                            .length;
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(d, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            count == 1 ? '1 employee' : '$count employees',
                            style: const TextStyle(fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              draft.add(d);
                            } else {
                              draft.remove(d);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setLocal(() => draft.clear()),
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  onSave(Set<String>.from(draft));
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    filterCtrl.dispose();
  }

  Future<void> _pickEmployees({
    required Set<String> selectedClocks,
    required void Function(Set<String>) onSave,
  }) async {
    if (_allEmployees.isEmpty) {
      await _loadEmployees();
    }
    if (!mounted) return;
    if (_allEmployees.isEmpty) {
      _showError('No employees loaded.');
      return;
    }
    final draft = Set<String>.from(selectedClocks);
    final filterCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = filterCtrl.text.trim().toLowerCase();
          final list = _employeesSorted.where((e) {
            if (q.isEmpty) return true;
            return e.name.toLowerCase().contains(q) ||
                e.clockNo.toLowerCase().contains(q) ||
                e.department.toLowerCase().contains(q) ||
                e.position.toLowerCase().contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Select people'),
            content: SizedBox(
              width: double.maxFinite,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    controller: filterCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search name, clock, department…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${draft.length} selected · ${list.length} shown',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).appColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final on = draft.contains(e.clockNo);
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(
                            e.name.isEmpty ? e.clockNo : e.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${e.clockNo} · ${e.department} · ${e.position}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              draft.add(e.clockNo);
                            } else {
                              draft.remove(e.clockNo);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setLocal(() => draft.clear()),
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  onSave(Set<String>.from(draft));
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    filterCtrl.dispose();
  }

  Widget _selectionSummary({
    required String title,
    required List<String> chips,
    required String emptyHint,
    required VoidCallback onEdit,
    String? subtitle,
  }) {
    final colors = Theme.of(context).appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.checklist, size: 18),
              label: Text(chips.isEmpty ? 'Select' : 'Edit'),
            ),
          ],
        ),
        if (subtitle != null)
          Text(subtitle, style: TextStyle(fontSize: 11, color: colors.textMuted)),
        if (chips.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(emptyHint, style: TextStyle(fontSize: 12, color: colors.textMuted)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips.take(24))
                  Chip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                if (chips.length > 24)
                  Chip(
                    label: Text('+${chips.length - 24} more',
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _copyRemoteConfigSnippet() async {
    final version = _pubVersionController.text.trim();
    final build = _pubBuildController.text.trim();
    final url = _updateUrlController.text.trim();
    final notes = _pubNotesController.text.trim();
    final sha = _pubShaController.text.trim();
    final snippet = [
      '# Default channel only (cohorts are Firestore updateChannels)',
      'latest_version = $version',
      'latest_build = $build',
      'download_url = $url',
      'force_update = $_pubForceUpdate',
      'release_notes = $notes',
      if (sha.isNotEmpty) 'apk_sha256 = $sha',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: snippet));
    if (mounted) {
      _showSuccess('Default-channel RC keys copied (cohorts use Firestore)');
    }
  }

  Map<String, dynamic> _readStageBlock(Map<String, dynamic> config, String key,
      {required bool defaultEnabled, required int defaultMinutes}) {
    final stage = (config['stages'] as Map<String, dynamic>?)?[key] as Map<String, dynamic>?;
    return {
      'enabled': stage?['enabled'] as bool? ?? defaultEnabled,
      'enabled_at': _parseEnabledAt(stage?['enabled_at']),
      'minutes': (stage?['minutes'] as num?)?.toInt() ?? defaultMinutes,
      'recipients_by_type': (stage?['recipients_by_type'] as Map<String, dynamic>?) ?? const {},
    };
  }

  DateTime? _parseEnabledAt(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Set<String> _stageRecipientsForUi(Map<String, dynamic> stageBlock, Set<String> fallback) {
    final mech = (stageBlock['recipients_by_type'] as Map<String, dynamic>)['mechanical'] as List?;
    return mech == null ? fallback : Set<String>.from(mech.map((e) => e.toString()));
  }

  Future<void> _loadNotificationConfig() async {
    try {
      final config = await _firestoreService.getNotificationConfig();
      final s1 = _readStageBlock(config, 'stage1', defaultEnabled: true, defaultMinutes: 5);
      final s2 = _readStageBlock(config, 'stage2', defaultEnabled: true, defaultMinutes: 10);
      final s3 = _readStageBlock(config, 'stage3', defaultEnabled: false, defaultMinutes: 30);
      final s4 = _readStageBlock(config, 'stage4', defaultEnabled: false, defaultMinutes: 60);
      if (!mounted) return;
      setState(() {
        _stage1Enabled = s1['enabled'] as bool;
        _stage2Enabled = s2['enabled'] as bool;
        _stage3Enabled = s3['enabled'] as bool;
        _stage4Enabled = s4['enabled'] as bool;
        _stage1LoadedEnabled = _stage1Enabled;
        _stage2LoadedEnabled = _stage2Enabled;
        _stage3LoadedEnabled = _stage3Enabled;
        _stage4LoadedEnabled = _stage4Enabled;
        _stage1LoadedEnabledAt = s1['enabled_at'] as DateTime?;
        _stage2LoadedEnabledAt = s2['enabled_at'] as DateTime?;
        _stage3LoadedEnabledAt = s3['enabled_at'] as DateTime?;
        _stage4LoadedEnabledAt = s4['enabled_at'] as DateTime?;
        _stage1MinController.text = (s1['minutes'] as int).toString();
        _stage2MinController.text = (s2['minutes'] as int).toString();
        _stage3MinController.text = (s3['minutes'] as int).toString();
        _stage4MinController.text = (s4['minutes'] as int).toString();
        _stage1Recipients = _stageRecipientsForUi(s1, {'onsite_managers', 'foremen'});
        _stage2Recipients = _stageRecipientsForUi(s2, {'onsite_dept_managers', 'onsite_workshop_manager'});
        _stage3Recipients = _stageRecipientsForUi(s3, {});
        _stage4Recipients = _stageRecipientsForUi(s4, {});
      });
    } catch (e) {
      _showError('Error loading notification config: $e');
    }
  }

  // ── Saves ─────────────────────────────────────────────────────────────────

  Future<void> _saveKillSwitch() async {
    if (!guardPersonaSubmit(context)) return;
    final build = int.tryParse(_minBuildController.text.trim());
    if (_minBuildController.text.trim().isNotEmpty && build == null) {
      _showError('Min supported build must be a whole number');
      return;
    }
    final url = _updateUrlController.text.trim();
    if (build != null && build > 0 && url.isEmpty) {
      _showError(
        'Set an Update download URL before enforcing a minimum build — '
        'otherwise users see a blocked screen with no install path.',
      );
      return;
    }
    final pubBuild = _pubBuildController.text.trim();
    if (pubBuild.isNotEmpty && int.tryParse(pubBuild) == null) {
      _showError('Default channel latest build must be a whole number');
      return;
    }
    final pubVersion = _pubVersionController.text.trim();
    if (pubVersion.isNotEmpty && url.isEmpty) {
      _showError(
        'Set the shared download URL before publishing a default channel version.',
      );
      return;
    }
    if (_inkEnabled) {
      final ib = _inkBuildController.text.trim();
      if (ib.isNotEmpty && int.tryParse(ib) == null) {
        _showError('Ink channel build must be a whole number');
        return;
      }
      if (_inkVersionController.text.trim().isNotEmpty &&
          url.isEmpty &&
          _inkUrlController.text.trim().isEmpty) {
        _showError('Ink channel needs a download URL (channel or shared).');
        return;
      }
    }
    if (_inkEnabled) {
      if (_inkDepartments.isEmpty && _inkClockNos.isEmpty) {
        _showError(
          'Department channel needs at least one department or person selected.',
        );
        return;
      }
    }
    if (_testersEnabled) {
      final tb = _testersBuildController.text.trim();
      if (tb.isNotEmpty && int.tryParse(tb) == null) {
        _showError('People channel build must be a whole number');
        return;
      }
      if (_testerClockNos.isEmpty && _testerDepartments.isEmpty) {
        _showError(
          'People / pilot channel needs at least one person or department selected.',
        );
        return;
      }
    }

    final defaultCh = UpdateChannel(
      id: 'default',
      enabled: _defaultEnabled,
      latestVersion: pubVersion,
      latestBuild: pubBuild,
      downloadUrl: url,
      releaseNotes: _pubNotesController.text.trim(),
      apkSha256: _pubShaController.text.trim(),
      forceUpdate: _pubForceUpdate,
    );
    final inkCh = UpdateChannel(
      id: 'ink',
      enabled: _inkEnabled,
      match: UpdateChannelMatch(
        departments: _inkDepartments.toList()..sort(),
        clockNos: _inkClockNos.toList()..sort(),
      ),
      latestVersion: _inkVersionController.text.trim(),
      latestBuild: _inkBuildController.text.trim(),
      downloadUrl: _inkUrlController.text.trim(),
      releaseNotes: _inkNotesController.text.trim(),
      apkSha256: _inkShaController.text.trim(),
      forceUpdate: _inkForce,
    );
    final testersCh = UpdateChannel(
      id: 'testers',
      enabled: _testersEnabled,
      match: UpdateChannelMatch(
        clockNos: _testerClockNos.toList()..sort(),
        departments: _testerDepartments.toList()..sort(),
      ),
      latestVersion: _testersVersionController.text.trim(),
      latestBuild: _testersBuildController.text.trim(),
      downloadUrl: _testersUrlController.text.trim(),
      releaseNotes: _testersNotesController.text.trim(),
      apkSha256: _testersShaController.text.trim(),
      forceUpdate: _testersForce,
    );

    if (_inkEnabled &&
        _inkForce &&
        defaultCh.latestBuild.isNotEmpty &&
        inkCh.latestBuild == defaultCh.latestBuild) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ink force same as default?'),
          content: const Text(
            'Ink force build equals the default channel build. Old APKs that '
            'only read default/legacy fields will prompt the whole factory. '
            'Prefer a higher ink-only build, or leave default lower.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      final payload = <String, dynamic>{
        if (build != null) 'minSupportedBuild': build,
        if (url.isNotEmpty) 'updateDownloadUrl': url,
        'updateChannels': {
          'default': defaultCh.toMap(),
          'ink': inkCh.toMap(),
          'testers': testersCh.toMap(),
        },
        // Legacy mirror of DEFAULT only — old APKs never see ink/testers.
        ...legacyPublishFieldsFromDefault(defaultCh),
        'publishedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .set(payload, SetOptions(merge: true));
      if (mounted) {
        _showSuccess(
          'Publish saved. New APKs use channels (Ink/Testers/Default). '
          'Old APKs only see the Default channel. Optional: Copy RC keys for default only.',
        );
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  Map<String, dynamic> _buildStageDoc(
      bool enabled, DateTime? enabledAt, int minutes, Set<String> recipients) {
    final list = recipients.toList();
    return {
      'enabled': enabled,
      'enabled_at': enabledAt?.toUtc().toIso8601String(),
      'minutes': minutes,
      'recipients_by_type': {
        'mechanical': list,
        'electrical': list,
        'mech/elec': list,
      },
    };
  }

  DateTime? _resolveEnabledAt({
    required bool currentlyEnabled,
    required bool wasEnabled,
    required DateTime? previousEnabledAt,
    required DateTime now,
  }) {
    if (currentlyEnabled && !wasEnabled) return now;
    return previousEnabledAt;
  }

  Future<void> _saveNotificationConfig() async {
    if (!guardPersonaSubmit(context)) return;
    final s1Min = int.tryParse(_stage1MinController.text) ?? 5;
    final s2Min = int.tryParse(_stage2MinController.text) ?? 10;
    final s3Min = int.tryParse(_stage3MinController.text) ?? 30;
    final s4Min = int.tryParse(_stage4MinController.text) ?? 60;

    if (_stage1Enabled && _stage2Enabled && s1Min >= s2Min) {
      _showError('Stage 1 minutes must be less than Stage 2');
      return;
    }

    final now = DateTime.now().toUtc();
    final s1At = _resolveEnabledAt(currentlyEnabled: _stage1Enabled, wasEnabled: _stage1LoadedEnabled, previousEnabledAt: _stage1LoadedEnabledAt, now: now);
    final s2At = _resolveEnabledAt(currentlyEnabled: _stage2Enabled, wasEnabled: _stage2LoadedEnabled, previousEnabledAt: _stage2LoadedEnabledAt, now: now);
    final s3At = _resolveEnabledAt(currentlyEnabled: _stage3Enabled, wasEnabled: _stage3LoadedEnabled, previousEnabledAt: _stage3LoadedEnabledAt, now: now);
    final s4At = _resolveEnabledAt(currentlyEnabled: _stage4Enabled, wasEnabled: _stage4LoadedEnabled, previousEnabledAt: _stage4LoadedEnabledAt, now: now);

    final newlyEnabled = <int>[
      if (_stage1Enabled && !_stage1LoadedEnabled) 1,
      if (_stage2Enabled && !_stage2LoadedEnabled) 2,
      if (_stage3Enabled && !_stage3LoadedEnabled) 3,
      if (_stage4Enabled && !_stage4LoadedEnabled) 4,
    ];

    if (newlyEnabled.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Enable Stage${newlyEnabled.length > 1 ? "s" : ""} ${newlyEnabled.join(", ")}?'),
          content: Text(
            'Recipients for the newly-enabled stage${newlyEnabled.length > 1 ? "s" : ""} '
            'will only be notified for jobs created from now on — existing open jobs will not trigger this stage.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    try {
      await _firestoreService.saveNotificationConfig({
        'stages': {
          'stage1': _buildStageDoc(_stage1Enabled, s1At, s1Min, _stage1Recipients),
          'stage2': _buildStageDoc(_stage2Enabled, s2At, s2Min, _stage2Recipients),
          'stage3': _buildStageDoc(_stage3Enabled, s3At, s3Min, _stage3Recipients),
          'stage4': _buildStageDoc(_stage4Enabled, s4At, s4Min, _stage4Recipients),
        },
        'creation_recipients_by_type': {
          'mechanical': ['onsite_mechanics'],
          'electrical': ['onsite_electricians'],
          'mech/elec': ['onsite_mechanics', 'onsite_electricians'],
          'building': ['onsite_building_maintenance', 'onsite_workshop_manager'],
          'specialist': ['onsite_prepress_specialist', 'onsite_workshop_manager'],
          'postPressSpecialist': ['onsite_postpress_specialist', 'onsite_workshop_manager'],
        },
        'excluded_job_types': ['maintenance', 'building', 'specialist', 'postPressSpecialist'],
        'last_updated': now.toIso8601String(),
        'updated_by_clock_no': _currentClockNo ?? '',
      });
      _stage1LoadedEnabled = _stage1Enabled; _stage2LoadedEnabled = _stage2Enabled;
      _stage3LoadedEnabled = _stage3Enabled; _stage4LoadedEnabled = _stage4Enabled;
      _stage1LoadedEnabledAt = s1At; _stage2LoadedEnabledAt = s2At;
      _stage3LoadedEnabledAt = s3At; _stage4LoadedEnabledAt = s4At;
      if (mounted) _showSuccess('Escalation config saved');
    } catch (e) {
      _showError('Error saving config: $e');
    }
  }

  Future<void> _clearEscalationStamps() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Escalation Stamps'),
        content: const Text(
          'This clears all Stage 1–4 stamps from open job cards, allowing the escalation to re-process them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { _showError('Session expired. Please log out and log back in.'); return; }
      await user.getIdToken(true);
      final result = await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('clearEscalationStamps')
          .call();
      if (mounted) _showSuccess('Cleared stamps from ${result.data['cleared'] ?? 0} job cards');
    } catch (e) {
      _showError('Error: $e');
    }
  }

  List<String> _parseClockNos(String raw) {
    return raw
        .split(RegExp(r'[\s,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _employeeNameForClock(String clockNo) {
    for (final e in _allEmployees) {
      if (e.clockNo == clockNo) return e.name;
    }
    return clockNo;
  }

  String? _clientDeliveryLabel(Map<String, dynamic> data) {
    final delivery = data['notificationDelivery'] as String?;
    final device = data['clientDevice'] as String?;
    if (delivery == 'inbox_only') {
      final label = switch (device) {
        'iphone' => 'iPhone web',
        'ipad' => 'iPad web',
        _ => device ?? 'web',
      };
      return 'Inbox only · $label';
    }
    if (device != null && device != 'android') {
      return 'Last device: $device';
    }
    return null;
  }

  /// Soft-update chase label from presence fields (null → Unknown on older APKs).
  String _clientAppVersionLabel(Map<String, dynamic> data) {
    final v = (data['clientAppVersion'] as String?)?.trim();
    final b = data['clientBuildNumber']?.toString().trim();
    final hasV = v != null && v.isNotEmpty;
    final hasB = b != null && b.isNotEmpty;
    if (!hasV && !hasB) return 'App: Unknown';
    if (hasV && hasB) return 'App: v$v (build $b)';
    if (hasV) return 'App: v$v';
    return 'App: build $b';
  }

  Widget _inboxOnlyBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 12, color: Colors.blue.shade800),
          const SizedBox(width: 4),
          Text(
            'Inbox',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionHealthIcon(Map<String, dynamic> data) {
    final perms = data['permissions'];
    final snap = DeviceHealthSnapshot.fromFirestorePermissions(
      perms is Map<String, dynamic>
          ? perms
          : perms is Map
              ? Map<String, dynamic>.from(perms)
              : null,
    );
    if (snap == null) {
      return Icon(Icons.help_outline, size: 16, color: Colors.grey.shade500);
    }
    if (snap.isAllGrantedInFirestore) {
      return const Icon(Icons.verified_outlined, size: 18, color: Colors.green);
    }
    return Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700);
  }

  Future<void> _sendBroadcast() async {
    if (!guardPersonaSubmit(context)) return;
    final title = _broadcastTitleController.text.trim();
    final body = _broadcastBodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showError('Title and message are required');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send to all employees?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Text(
              'Every employee with an FCM token will receive this push notification. '
              'Off-site employees will also receive an inbox item.',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).appColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isBroadcasting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isBroadcasting = false);
        _showError('Session expired. Please log out and log back in.');
        return;
      }
      await user.getIdToken(true); // ensure token is fresh before admin CF call
      final result = await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('broadcastUpdateNotice')
          .call({'callerClockNo': _currentClockNo ?? '22', 'title': title, 'body': body});
      setState(() {
        _lastBroadcastResult = Map<String, dynamic>.from(result.data as Map);
        _isBroadcasting = false;
      });
    } catch (e) {
      setState(() => _isBroadcasting = false);
      _showError('Error: $e');
    }
  }

  Future<void> _sendTargetedBroadcast() async {
    if (!guardPersonaSubmit(context)) return;
    final title = _broadcastTitleController.text.trim();
    final body = _broadcastBodyController.text.trim();
    final clockNos = _parseClockNos(_targetedClockNosController.text);
    if (title.isEmpty || body.isEmpty) {
      _showError('Title and message are required');
      return;
    }
    if (clockNos.isEmpty) {
      _showError('Enter at least one clock number');
      return;
    }

    final names = clockNos
        .map((c) => '${_employeeNameForClock(c)} ($c)')
        .join('\n');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send to ${clockNos.length} employee${clockNos.length == 1 ? '' : 's'}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              Text(names, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isTargetedBroadcasting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isTargetedBroadcasting = false);
        _showError('Session expired. Please log out and log back in.');
        return;
      }
      await user.getIdToken(true);
      final result = await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('broadcastUpdateNotice')
          .call({
        'callerClockNo': _currentClockNo ?? '22',
        'title': title,
        'body': body,
        'clockNos': clockNos,
      });
      setState(() {
        _lastTargetedBroadcastResult = Map<String, dynamic>.from(result.data as Map);
        _isTargetedBroadcasting = false;
      });
    } catch (e) {
      setState(() => _isTargetedBroadcasting = false);
      _showError('Error: $e');
    }
  }

  // ── Employee CRUD ─────────────────────────────────────────────────────────

  void _bulkDelete() async {
    for (final clockNo in _selectedClockNos) {
      await _firestoreService.deleteEmployee(clockNo);
    }
    _selectedClockNos.clear();
    EmployeeRosterCache.instance.invalidate();
    await _loadEmployees();
    if (mounted) setState(() {});
  }

  void _deleteEmployee(String clockNo) async {
    final ok = await _confirmDialog('Delete Employee', 'Are you sure?');
    if (!ok) return;
    try {
      await _firestoreService.deleteEmployee(clockNo);
      EmployeeRosterCache.instance.invalidate();
      await _loadEmployees();
      if (mounted) _showSuccess('Employee deleted');
    } catch (e) { _showError('Error: $e'); }
  }

  /// Toggle [Employee.registrationLocked] without opening the full editor.
  /// Matches `linkEmployeeAccount` field `registration_locked` (Phase 11 prep).
  Future<void> _setRegistrationLocked(Employee emp, bool locked) async {
    try {
      await _firestoreService.updateEmployee(
        emp.copyWith(registrationLocked: locked),
      );
      EmployeeRosterCache.instance.invalidate();
      await _loadEmployees();
      if (!mounted) return;
      _showSuccess(
        locked
            ? 'Registration locked for #${emp.clockNo} — new sign-ups blocked'
            : 'Registration unlocked for #${emp.clockNo} — new hire can register',
      );
    } catch (e) {
      _showError('Could not update registration lock: $e');
    }
  }

  void _showEmployeeDialog([Employee? employee]) {
    final isEdit = employee != null;
    final existing = employee;
    final cnCtrl = TextEditingController(text: existing?.clockNo ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final posCtrl = TextEditingController(text: existing?.position ?? '');
    final deptCtrl = TextEditingController(text: existing?.department ?? '');
    final fcmCtrl = TextEditingController(text: existing?.fcmToken ?? '');
    bool isOnSite = existing?.isOnSite ?? true;
    // Default unlocked so existing open registration behaviour is unchanged
    // until admin locks high-value clocks.
    bool registrationLocked = existing?.registrationLocked ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isEdit ? 'Edit Employee' : 'Add Employee'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: cnCtrl, decoration: const InputDecoration(labelText: 'Clock No *'), enabled: !isEdit),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name *')),
              const SizedBox(height: 12),
              TextField(controller: posCtrl, decoration: const InputDecoration(labelText: 'Position *')),
              const SizedBox(height: 12),
              TextField(controller: deptCtrl, decoration: const InputDecoration(labelText: 'Department *')),
              const SizedBox(height: 12),
              TextField(controller: fcmCtrl, decoration: const InputDecoration(labelText: 'FCM Token')),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('On Site'),
                value: isOnSite,
                onChanged: (v) => setS(() => isOnSite = v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Registration locked'),
                subtitle: Text(
                  registrationLocked
                      ? 'New users cannot claim this clock (already linked can still re-login).'
                      : 'Anyone with the clock number can register if email rules allow.',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).appColors.textMuted),
                ),
                secondary: Icon(
                  registrationLocked ? Icons.lock_outline : Icons.lock_open_outlined,
                  color: registrationLocked ? Colors.orange : null,
                ),
                value: registrationLocked,
                onChanged: (v) => setS(() => registrationLocked = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (existing != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    existing.isAccountLinked
                        ? 'Account linked (uid present)'
                        : 'Not linked yet — unlock to allow first registration',
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).appColors.textMuted),
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (cnCtrl.text.isEmpty || nameCtrl.text.isEmpty || posCtrl.text.isEmpty || deptCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Required fields missing'), backgroundColor: Colors.red),
                  );
                  return;
                }
                final nav = Navigator.of(ctx);
                final msg = ScaffoldMessenger.of(ctx);
                try {
                  final emp = Employee(
                    clockNo: cnCtrl.text, name: nameCtrl.text, position: posCtrl.text,
                    department: deptCtrl.text, isOnSite: isOnSite,
                    fcmToken: fcmCtrl.text.isEmpty ? null : fcmCtrl.text,
                    fcmTokenUpdatedAt: existing?.fcmTokenUpdatedAt,
                    registrationLocked: registrationLocked,
                    uid: existing?.uid,
                    isAdmin: existing?.isAdmin ?? false,
                  );
                  if (isEdit) {
                    await _firestoreService.updateEmployee(emp);
                  } else {
                    await _firestoreService.createEmployee(emp);
                  }
                  EmployeeRosterCache.instance.invalidate();
                  nav.pop();
                  await _loadEmployees();
                  msg.showSnackBar(SnackBar(content: Text('Employee ${isEdit ? 'updated' : 'added'}')));
                } catch (e) { msg.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
              },
              child: Text(isEdit ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Structure CRUD ────────────────────────────────────────────────────────

  void _deleteDepartment(String dept) async {
    final ok = await _confirmDialog('Delete Department', 'This deletes all areas and machines in $dept.');
    if (!ok) return;
    final updated = Map<String, dynamic>.from(_structure);
    updated.remove(dept);
    await _firestoreService.updateFactoryStructure(updated);
    if (selectedDeptForArea == dept) selectedDeptForArea = null;
    if (selectedDeptForMachine == dept) {
      selectedDeptForMachine = null;
      selectedAreaForMachine = null;
    }
    await _loadStructure();
  }

  void _deleteArea(String dept, String area) async {
    final ok = await _confirmDialog('Delete Area', 'This deletes all machines in $area.');
    if (!ok) return;
    final updated = Map<String, dynamic>.from(_structure);
    final deptMap = Map<String, dynamic>.from(updated[dept] as Map<String, dynamic>);
    deptMap.remove(area);
    updated[dept] = deptMap;
    await _firestoreService.updateFactoryStructure(updated);
    if (selectedAreaForMachine == area && selectedDeptForMachine == dept) {
      selectedAreaForMachine = null;
    }
    await _loadStructure();
  }

  void _deleteMachine(String dept, String area, String machine) async {
    final ok = await _confirmDialog('Delete Machine', 'Remove $machine?');
    if (!ok) return;
    final updated = Map<String, dynamic>.from(_structure);
    final deptMap = Map<String, dynamic>.from(updated[dept] as Map<String, dynamic>);
    final machines = List<dynamic>.from(deptMap[area] as List<dynamic>);
    machines.remove(machine);
    deptMap[area] = machines;
    updated[dept] = deptMap;
    await _firestoreService.updateFactoryStructure(updated);
    await _loadStructure();
  }

  List<String> get _structureDepartments {
    final depts = _structure.keys.map((e) => e.toString()).toList()..sort();
    return depts;
  }

  List<String> _areasForDepartment(String? dept) {
    if (dept == null || !_structure.containsKey(dept)) return [];
    final areas = (_structure[dept] as Map<String, dynamic>).keys.map((e) => e.toString()).toList()..sort();
    return areas;
  }

  ({int departments, int areas, int machines}) _structureStats() {
    var areaCount = 0;
    var machineCount = 0;
    _structure.forEach((_, areas) {
      if (areas is Map) {
        (areas as Map<String, dynamic>).forEach((_, machines) {
          areaCount++;
          if (machines is List) machineCount += machines.length;
        });
      }
    });
    return (departments: _structure.length, areas: areaCount, machines: machineCount);
  }

  Widget _structureStatChip(String label, int value) {
    final colors = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.inputFill),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: colors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _structureChoiceChips({
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    if (options.isEmpty) {
      return Text(
        'No departments yet — add one below.',
        style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((option) => ChoiceChip(
        label: Text(option, style: const TextStyle(fontSize: 12)),
        selected: selected == option,
        onSelected: (_) => onSelected(option),
        selectedColor: kBrandOrange,
        labelStyle: TextStyle(color: selected == option ? Colors.white : Theme.of(context).appColors.chipUnselectedLabel),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
  }

  Future<void> _addDepartment() async {
    if (!guardPersonaSubmit(context)) return;
    final name = deptController.text.trim();
    if (name.isEmpty) return;
    if (_structure.containsKey(name)) {
      _showError('Department already exists');
      return;
    }
    final updated = Map<String, dynamic>.from(_structure);
    updated[name] = <String, dynamic>{};
    await _firestoreService.updateFactoryStructure(updated);
    deptController.clear();
    await _loadStructure();
    if (mounted) _showSuccess('Department added');
  }

  Future<void> _addArea() async {
    if (!guardPersonaSubmit(context)) return;
    if (selectedDeptForArea == null || areaController.text.trim().isEmpty) return;
    final areaName = areaController.text.trim();
    final updated = Map<String, dynamic>.from(_structure);
    final deptMap = Map<String, dynamic>.from(updated[selectedDeptForArea] as Map<String, dynamic>);
    if (deptMap.containsKey(areaName)) {
      _showError('Area already exists in this department');
      return;
    }
    deptMap[areaName] = <String>[];
    updated[selectedDeptForArea!] = deptMap;
    await _firestoreService.updateFactoryStructure(updated);
    areaController.clear();
    await _loadStructure();
    if (mounted) _showSuccess('Area added');
  }

  Future<void> _addMachine() async {
    if (!guardPersonaSubmit(context)) return;
    if (selectedDeptForMachine == null || selectedAreaForMachine == null || machineController.text.trim().isEmpty) return;
    final machineName = machineController.text.trim();
    final updated = Map<String, dynamic>.from(_structure);
    final deptMap = Map<String, dynamic>.from(updated[selectedDeptForMachine] as Map<String, dynamic>);
    final machines = List<dynamic>.from(deptMap[selectedAreaForMachine] as List<dynamic>);
    if (machines.map((e) => e.toString()).contains(machineName)) {
      _showError('Machine / part already exists in this area');
      return;
    }
    machines.add(machineName);
    deptMap[selectedAreaForMachine!] = machines;
    updated[selectedDeptForMachine!] = deptMap;
    await _firestoreService.updateFactoryStructure(updated);
    machineController.clear();
    await _loadStructure();
    if (mounted) _showSuccess('Machine added');
  }

  // ── CSV ────────────────────────────────────────────────────────────────────

  void _exportTemplate() {
    final csv = Csv().encode([
      ['clockNo', 'name', 'position', 'department', 'isOnSite', 'fcmToken'],
      ['', '', '', '', 'true', ''],
    ]);
    _shareOrDownload(csv, 'employees_template.csv');
  }

  void _shareOrDownload(String csv, String filename) {
    if (kIsWeb) {
      final blob = html.Blob([csv], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)..download = filename..click();
      html.Url.revokeObjectUrl(url);
    } else {
      SharePlus.instance.share(ShareParams(text: csv, subject: filename));
    }
  }

  void _importCsv() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final csvString = file.bytes != null
          ? String.fromCharCodes(file.bytes!)
          : (file.path != null ? await File(file.path!).readAsString() : null);
      if (csvString == null) return;

      final table = Csv().decode(csvString);
      if (table.isEmpty || table[0].length < 6) {
        if (mounted) _showError('Invalid CSV format');
        return;
      }
      final headers = table[0].map((e) => e.toString().trim().toLowerCase()).toList();
      const expected = ['clockno', 'name', 'position', 'department', 'isonsite', 'fcmtoken'];
      if (!expected.every(headers.contains)) {
        if (mounted) _showError('Invalid CSV headers');
        return;
      }
      final rows = table.skip(1).map((row) => {
        'clockNo': row[headers.indexOf('clockno')].toString().trim(),
        'name': row[headers.indexOf('name')].toString().trim(),
        'position': row[headers.indexOf('position')].toString().trim(),
        'department': row[headers.indexOf('department')].toString().trim(),
        'isOnSite': _parseBool(row[headers.indexOf('isonsite')].toString().trim()),
        'fcmToken': row[headers.indexOf('fcmtoken')].toString().trim().isEmpty ? null : row[headers.indexOf('fcmtoken')].toString().trim(),
      }).toList();

      if (!mounted) return;
      bool deleteAll = false;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Preview Import'),
            content: SizedBox(
              width: double.maxFinite, height: 400,
              child: Column(children: [
                CheckboxListTile(
                  title: const Text('Delete all existing employees first'),
                  value: deleteAll,
                  onChanged: (v) => setS(() => deleteAll = v ?? false),
                ),
                Expanded(child: ListView(
                  children: rows.map((r) => ListTile(
                    dense: true,
                    title: Text('${r['clockNo']} — ${r['name']}'),
                    subtitle: Text('${r['position']} · ${r['department']}'),
                  )).toList(),
                )),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  final nav = Navigator.of(ctx);
                  final msg = ScaffoldMessenger.of(ctx);
                  nav.pop();
                  if (deleteAll) await _firestoreService.deleteAllEmployees();
                  int imported = 0, skipped = 0;
                  for (final row in rows) {
                    if (row['clockNo'].toString().isEmpty) { skipped++; continue; }
                    try {
                      await _firestoreService.updateEmployee(Employee(
                        clockNo: row['clockNo'] as String, name: row['name'] as String,
                        position: row['position'] as String, department: row['department'] as String,
                        isOnSite: row['isOnSite'] as bool, fcmToken: row['fcmToken'] as String?,
                      ));
                      imported++;
                    } catch (_) { skipped++; }
                  }
                  _loadEmployees();
                  msg.showSnackBar(SnackBar(content: Text('Imported $imported, skipped $skipped')));
                },
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError('Import failed: $e');
    }
  }

  bool _parseBool(String v) {
    final l = v.toLowerCase();
    return l == 'true' || l == '1' || l == 'yes' || l == 'on';
  }

  // ── Feedback helpers ──────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2E7D32)),
    );
  }

  Future<bool> _confirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Design helpers ────────────────────────────────────────────────────────

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Theme.of(context).appColors.textMuted,
        ),
      ),
    );
  }

  Widget _settingsCard({required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).appColors.cardSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).appColors.inputFill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Factory Admin'),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: kBrandOrange,
          labelColor: kBrandOrange,
          unselectedLabelColor: Theme.of(context).appColors.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined, size: 18), text: 'Overview'),
            Tab(icon: Icon(Icons.people_outline, size: 18), text: 'Employees'),
            Tab(icon: Icon(Icons.account_tree_outlined, size: 18), text: 'Structures'),
            Tab(icon: Icon(Icons.location_on_outlined, size: 18), text: 'On Site'),
            Tab(icon: Icon(Icons.campaign_outlined, size: 18), text: 'Comms'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildEmployeesTab(),
          _buildStructuresTab(),
          _buildOnsiteTab(),
          _buildCommsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: _showEmployeeDialog,
              backgroundColor: kBrandOrange,
              child: const Icon(Icons.person_add_outlined, color: Colors.white),
            )
          : null,
    );
  }

  // ── On Site tab ───────────────────────────────────────────────────────────

  // Compact "on site for" duration, used by the 14h-stuck flag display.
  String _onSiteDuration(DateTime since) {
    final d = DateTime.now().difference(since);
    if (d.inHours >= 24) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  Widget _buildOnsiteTab() {
    final colors = Theme.of(context).appColors;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('employees').where('isOnSite', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_off_outlined, size: 48, color: colors.textMuted),
              const SizedBox(height: 12),
              Text('No employees currently on site', style: TextStyle(color: colors.textMuted)),
            ]),
          );
        }
        // Parse rows + compute the on-site-since duration and the 14h-stuck flag
        // (surfaces sessions where geofence/permissions likely stopped working).
        final now = DateTime.now();
        var flaggedCount = 0;
        var unknownAppCount = 0;
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final since = data['lastOnSiteAt'] is Timestamp
              ? (data['lastOnSiteAt'] as Timestamp).toDate()
              : null;
          final stuck = since != null && now.difference(since).inHours >= 14;
          if (stuck) flaggedCount++;
          final ver = (data['clientAppVersion'] as String?)?.trim();
          final build = data['clientBuildNumber']?.toString().trim();
          if ((ver == null || ver.isEmpty) && (build == null || build.isEmpty)) {
            unknownAppCount++;
          }
          grouped
              .putIfAbsent((data['department'] as String? ?? 'Unknown').trim(), () => [])
              .add({...data, 'id': doc.id, 'since': since, 'stuck': stuck});
        }
        final depts = grouped.keys.toList()..sort();
        return Column(children: [
          Container(
            width: double.infinity,
            color: colors.wasteGreenSurface,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(children: [
              Icon(Icons.people, size: 16, color: colors.wasteGreenDark),
              const SizedBox(width: 8),
              Text(
                '${docs.length} employee${docs.length == 1 ? '' : 's'} on site',
                style: TextStyle(fontWeight: FontWeight.w600, color: colors.wasteGreenDark, fontSize: 13),
              ),
            ]),
          ),
          if (flaggedCount > 0)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$flaggedCount on site 14h+ — check their geofence / location permissions',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ]),
            ),
          if (unknownAppCount > 0)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(children: [
                Icon(Icons.phone_android_outlined, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$unknownAppCount with unknown app version — open the latest APK once so presence can report build',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade900, fontSize: 12),
                  ),
                ),
              ]),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final dept in depts) ...[
                  _sectionHeader(dept.toUpperCase()),
                  for (final emp in grouped[dept]!)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: colors.cardSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: (emp['stuck'] as bool) ? Colors.red.shade100 : colors.wasteGreenSurface,
                          child: Text(
                            (emp['name'] as String? ?? '?')[0].toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold, color: (emp['stuck'] as bool) ? Colors.red.shade700 : colors.wasteGreenDark),
                          ),
                        ),
                        title: Text(emp['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          [
                            emp['since'] != null
                                ? '${emp['position'] as String? ?? '—'}  •  on site ${_onSiteDuration(emp['since'] as DateTime)}'
                                : (emp['position'] as String? ?? '—'),
                            _clientAppVersionLabel(emp),
                            if (_clientDeliveryLabel(emp) != null)
                              _clientDeliveryLabel(emp)!,
                          ].join('\n'),
                          style: TextStyle(fontSize: 12, color: (emp['stuck'] as bool) ? Colors.red.shade700 : colors.textMuted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (emp['notificationDelivery'] == 'inbox_only') ...[
                              _inboxOnlyBadge(),
                              const SizedBox(width: 6),
                            ],
                            _permissionHealthIcon(emp),
                            const SizedBox(width: 6),
                            if (emp['stuck'] as bool)
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.red, size: 18)
                            else
                              Text(
                                emp['id'] as String? ?? '',
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: colors.textMuted),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ]);
      },
    );
  }

  // ── Employees tab ─────────────────────────────────────────────────────────

  Widget _buildPresencePill(Employee emp) {
    final colors = Theme.of(context).appColors;
    return GestureDetector(
      onTap: () => _firestoreService.adminSetPresence(emp.clockNo, !emp.isOnSite),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: emp.isOnSite ? colors.wasteGreenSurface : colors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: emp.isOnSite ? colors.wasteGreen.withValues(alpha: 0.35) : colors.inputFill,
          ),
        ),
        child: Text(
          emp.isOnSite ? 'On Site' : 'Off Site',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: emp.isOnSite ? colors.wasteGreenDark : colors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeesTab() {
    final colors = Theme.of(context).appColors;
    if (!_employeesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _employeeSearchController,
            decoration: _inputDecoration('Search employees', hint: 'Name, clock no, department…'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _exportTemplate,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Template'),
              ),
              OutlinedButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: const Text('Import'),
              ),
              if (_selectedClockNos.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _bulkDelete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Delete ${_selectedClockNos.length}'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
                ),
            ],
          ),
        ])),
      ),
      Expanded(
        child: _allEmployees.isEmpty
            ? Center(
                child: Text(
                  _employeeSearchController.text.isEmpty
                      ? 'No employees found'
                      : 'No employees match your search',
                  style: TextStyle(color: colors.textMuted),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _loadEmployees(force: true),
                child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              itemCount: _displayedEmployees.length,
              itemBuilder: (context, index) {
                final emp = _displayedEmployees[index];
                final selected = _selectedClockNos.contains(emp.clockNo);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colors.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: selected ? kBrandOrange.withValues(alpha: 0.45) : colors.inputFill,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Checkbox(
                        value: selected,
                        activeColor: kBrandOrange,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedClockNos.add(emp.clockNo);
                          } else {
                            _selectedClockNos.remove(emp.clockNo);
                          }
                        }),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.inputFill,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#${emp.clockNo}',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                emp.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (emp.registrationLocked)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
                              ),
                            _buildPresencePill(emp),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            [
                              '${emp.position} · ${emp.department}',
                              if (emp.registrationLocked)
                                'Registration locked'
                              else if (!emp.isAccountLinked)
                                'Open for registration'
                              else
                                'Account linked',
                              if (emp.isInboxOnlyDelivery)
                                'Inbox only · ${emp.clientDevice ?? 'web'}',
                            ].join('\n'),
                            style: TextStyle(fontSize: 12, color: colors.textMuted),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                      ),
                      Column(children: [
                        IconButton(
                          icon: Icon(
                            emp.registrationLocked
                                ? Icons.lock_outline
                                : Icons.lock_open_outlined,
                            size: 18,
                            color: emp.registrationLocked ? Colors.orange : null,
                          ),
                          tooltip: emp.registrationLocked
                              ? 'Unlock registration (allow new hire)'
                              : 'Lock registration (block new claims)',
                          onPressed: () => _setRegistrationLocked(
                            emp,
                            !emp.registrationLocked,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit',
                          onPressed: () => _showEmployeeDialog(emp),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          tooltip: 'Delete',
                          onPressed: () => _deleteEmployee(emp.clockNo),
                          visualDensity: VisualDensity.compact,
                        ),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
      ),
    ]);
  }

  // ── Structures tab ────────────────────────────────────────────────────────

  Widget _buildStructuresTab() {
    final colors = Theme.of(context).appColors;
    final stats = _structureStats();
    final structureList = _buildStructureList();

    return SingleChildScrollView(
      padding: ScreenInsets.symmetricScroll(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _settingsCard(child: TextField(
          controller: structureSearchController,
          decoration: _inputDecoration('Search structures', hint: 'Department, area, machine…'),
          onChanged: (_) => setState(() {}),
        )),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _structureStatChip('Departments', stats.departments)),
            const SizedBox(width: 8),
            Expanded(child: _structureStatChip('Areas', stats.areas)),
            const SizedBox(width: 8),
            Expanded(child: _structureStatChip('Machines', stats.machines)),
          ],
        ),
        const SizedBox(height: 16),
        _sectionHeader('FACTORY STRUCTURE'),
        if (structureList.isEmpty)
          _settingsCard(child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                structureSearchController.text.isEmpty
                    ? 'No structure defined yet'
                    : 'No matches for your search',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            ),
          ))
        else
          ...structureList,
        const SizedBox(height: 8),
        _sectionHeader('ADD NEW'),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.domain_outlined, color: kBrandOrange, size: 18),
            const SizedBox(width: 8),
            const Text('Department', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: deptController, decoration: _inputDecoration('Department name')),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _addDepartment,
              style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
              child: const Text('Add Department'),
            ),
          ),
        ])),
        const SizedBox(height: 12),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.layers_outlined, color: kBrandOrange, size: 18),
            const SizedBox(width: 8),
            const Text('Area', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text('Select a department, then enter the area name.', style: TextStyle(fontSize: 12, color: colors.textMuted)),
          const SizedBox(height: 10),
          _structureChoiceChips(
            options: _structureDepartments,
            selected: selectedDeptForArea,
            onSelected: (dept) => setState(() => selectedDeptForArea = dept),
          ),
          const SizedBox(height: 10),
          TextField(controller: areaController, decoration: _inputDecoration('Area name')),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _addArea,
              style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
              child: const Text('Add Area'),
            ),
          ),
        ])),
        const SizedBox(height: 12),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.precision_manufacturing_outlined, color: kBrandOrange, size: 18),
            const SizedBox(width: 8),
            const Text('Machine / Part', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text('Select department and area, then add the machine or part.', style: TextStyle(fontSize: 12, color: colors.textMuted)),
          const SizedBox(height: 10),
          _structureChoiceChips(
            options: _structureDepartments,
            selected: selectedDeptForMachine,
            onSelected: (dept) => setState(() { selectedDeptForMachine = dept; selectedAreaForMachine = null; }),
          ),
          if (selectedDeptForMachine != null) ...[
            const SizedBox(height: 8),
            _structureChoiceChips(
              options: _areasForDepartment(selectedDeptForMachine),
              selected: selectedAreaForMachine,
              onSelected: (area) => setState(() => selectedAreaForMachine = area),
            ),
          ],
          const SizedBox(height: 10),
          TextField(controller: machineController, decoration: _inputDecoration('Machine / Part name')),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _addMachine,
              style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
              child: const Text('Add Machine / Part'),
            ),
          ),
        ])),
        const SizedBox(height: 16),
      ]),
    );
  }

  List<Widget> _buildStructureList() {
    final query = structureSearchController.text.toLowerCase();
    final filtered = <String, dynamic>{};
    _structure.forEach((dept, areas) {
      if (dept.toLowerCase().contains(query)) {
        filtered[dept] = areas;
      } else {
        final filtAreas = <String, dynamic>{};
        (areas as Map<String, dynamic>).forEach((area, machines) {
          if (area.toLowerCase().contains(query) || (machines as List).any((m) => m.toString().toLowerCase().contains(query))) {
            filtAreas[area] = machines;
          }
        });
        if (filtAreas.isNotEmpty) filtered[dept] = filtAreas;
      }
    });

    final colors = Theme.of(context).appColors;
    return filtered.entries.map((deptEntry) {
      final areaMap = deptEntry.value as Map<String, dynamic>;
      final machineCount = areaMap.values
          .whereType<List>()
          .fold<int>(0, (total, machines) => total + machines.length);
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: colors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: kBrandOrange.withValues(alpha: 0.12),
              child: const Icon(Icons.domain_outlined, size: 16, color: kBrandOrange),
            ),
            title: Text(deptEntry.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              '${areaMap.length} area${areaMap.length == 1 ? '' : 's'} · $machineCount machine${machineCount == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              onPressed: () => _deleteDepartment(deptEntry.key),
              visualDensity: VisualDensity.compact,
            ),
            children: areaMap.entries.map((areaEntry) {
              final machines = areaEntry.value as List;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                color: colors.inputFill.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(areaEntry.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${machines.length} machine${machines.length == 1 ? '' : 's'} / parts',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                      onPressed: () => _deleteArea(deptEntry.key, areaEntry.key),
                      visualDensity: VisualDensity.compact,
                    ),
                    children: machines.map((machine) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.precision_manufacturing_outlined, size: 16, color: kBrandOrange),
                      title: Text(machine.toString(), style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                        onPressed: () => _deleteMachine(deptEntry.key, areaEntry.key, machine.toString()),
                        visualDensity: VisualDensity.compact,
                      ),
                    )).toList(),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }).toList();
  }

  Widget _channelHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Theme.of(context).appColors.textMuted),
          ),
        ],
      ),
    );
  }

  // When a detail form is pushed on top of this screen, parent setState must
  // also rebuild that pushed body (closures capture this State).
  VoidCallback? _rebuildDetailPage;

  void _pushAdminPage(String title, WidgetBuilder bodyBuilder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: Theme.of(ctx).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
          ),
          body: StatefulBuilder(
            builder: (context, setLocal) {
              _rebuildDetailPage = () => setLocal(() {});
              return bodyBuilder(context);
            },
          ),
        ),
      ),
    ).whenComplete(() {
      _rebuildDetailPage = null;
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rebuildDetailPage?.call();
  }

  Widget _hubTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).appColors.cardSurface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? kBrandOrange),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // ── Overview tab (grouped hub — detail forms open on push) ────────────────

  Widget _buildOverviewTab() {
    final muted = Theme.of(context).appColors.textMuted;
    return ListView(
      padding: ScreenInsets.symmetricScroll(context),
      children: [
        Text(
          'Grouped by job. Forms open on their own screen — Feedback triage is on Home for admins.',
          style: TextStyle(fontSize: 12, color: muted, height: 1.35),
        ),
        const SizedBox(height: 16),
        _sectionHeader('APP & RELEASES'),
        _hubTile(
          icon: Icons.system_update,
          title: 'App releases',
          subtitle: 'Publish channels, soft/force update, kill-switch',
          onTap: () => _pushAdminPage(
            'App releases',
            (_) => SingleChildScrollView(
              padding: ScreenInsets.symmetricScroll(context),
              child: _buildAppReleasesBody(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionHeader('JOB CARDS'),
        _hubTile(
          icon: Icons.notifications_active_outlined,
          title: 'Escalation rules',
          subtitle: 'Unassigned job stages and who gets notified',
          onTap: () => _pushAdminPage(
            'Escalation rules',
            (_) => SingleChildScrollView(
              padding: ScreenInsets.symmetricScroll(context),
              child: _buildEscalationConfigSection(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionHeader('SITE'),
        _hubTile(
          icon: Icons.map_outlined,
          title: 'Site & location',
          subtitle: 'Geofence editor and location force-checks',
          onTap: () => _pushAdminPage(
            'Site & location',
            (_) => SingleChildScrollView(
              padding: ScreenInsets.symmetricScroll(context),
              child: _buildLocationBody(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionHeader('MODULES'),
        _hubTile(
          icon: Icons.extension_outlined,
          title: 'Module gates',
          subtitle: 'Waste / Fleet on-off and Copper dashboard',
          iconColor: const Color(0xFF22863A),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminModulesScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _sectionHeader('TOOLS'),
        _hubTile(
          icon: Icons.build_outlined,
          title: 'Developer & device tools',
          subtitle: 'Scan Tester, notification diagnostics, kiosk',
          iconColor: const Color(0xFF3B82F6),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminToolsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildAppReleasesBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── App Update Control (channels + kill-switch) ─────────────────────
        _sectionHeader('APP UPDATE CONTROL'),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.system_update, color: kBrandOrange, size: 18),
            const SizedBox(width: 8),
            const Text('Publish release', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Channels: Default (everyone), Departments, People/pilot. '
            'Pick departments or people from your live employee lists. '
            'Soft = Home banner only. Force = full-screen until install. '
            'Match order: People → Departments → Default. Old APKs only see Default.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
          ),
          if (_thisDeviceBuildLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'This device: $_thisDeviceBuildLabel',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kBrandOrange),
            ),
          ],
          const SizedBox(height: 12),
          _killSwitchLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Shared download URL (fallback)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _updateUrlController,
                    decoration: _inputDecoration('Update download URL', hint: 'https://…/app-release.apk'),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  _channelHeader('Default (factory)', 'Banner if soft · full-screen if force'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled', style: TextStyle(fontSize: 14)),
                    value: _defaultEnabled,
                    activeThumbColor: kBrandOrange,
                    onChanged: (v) => setState(() => _defaultEnabled = v),
                  ),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _pubVersionController,
                        decoration: _inputDecoration('Latest version', hint: '2.3.0'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _pubBuildController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Latest build', hint: '135'),
                      ),
                    ),
                  ]),
                  TextButton.icon(
                    onPressed: _fillPublishFromThisDevice,
                    icon: const Icon(Icons.phone_android, size: 18),
                    label: const Text('Fill version from this device'),
                  ),
                  TextField(
                    controller: _pubNotesController,
                    maxLines: 2,
                    decoration: _inputDecoration('Release notes', hint: 'Optional'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pubShaController,
                    decoration: _inputDecoration('APK SHA-256 (optional)', hint: '64 hex chars'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Force update (default channel)', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      'Full-screen block for everyone on Default. Soft = banner only.',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).appColors.textMuted),
                    ),
                    value: _pubForceUpdate,
                    activeThumbColor: kBrandOrange,
                    onChanged: (v) => setState(() => _pubForceUpdate = v),
                  ),
                  const Divider(height: 28),
                  _channelHeader(
                    'Departments channel',
                    'Any departments (and optional people) — e.g. Ink Factory only',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled', style: TextStyle(fontSize: 14)),
                    value: _inkEnabled,
                    activeThumbColor: kBrandOrange,
                    onChanged: (v) => setState(() => _inkEnabled = v),
                  ),
                  if (_inkEnabled) ...[
                    _selectionSummary(
                      title: 'Departments',
                      chips: _inkDepartments.toList()..sort(),
                      emptyHint: 'No departments selected.',
                      subtitle: 'From employee list + factory structure.',
                      onEdit: () => _pickDepartments(
                        selected: _inkDepartments,
                        onSave: (s) => setState(() => _inkDepartments = s),
                      ),
                    ),
                    _selectionSummary(
                      title: 'People (optional)',
                      chips: _employeeChipLabels(_inkClockNos),
                      emptyHint: 'Optional — also include specific people.',
                      onEdit: () => _pickEmployees(
                        selectedClocks: _inkClockNos,
                        onSave: (s) => setState(() => _inkClockNos = s),
                      ),
                    ),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _inkVersionController,
                          decoration: _inputDecoration('Version', hint: '2.3.0'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inkBuildController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('Build', hint: '136'),
                        ),
                      ),
                    ]),
                    TextButton.icon(
                      onPressed: _fillInkFromThisDevice,
                      icon: const Icon(Icons.phone_android, size: 18),
                      label: const Text('Fill from this device'),
                    ),
                    TextField(
                      controller: _inkUrlController,
                      decoration: _inputDecoration('Channel APK URL (optional)', hint: 'Empty = shared URL'),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inkNotesController,
                      maxLines: 2,
                      decoration: _inputDecoration('Notes', hint: 'Module-specific changes'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inkShaController,
                      decoration: _inputDecoration('SHA-256 (optional)', hint: '64 hex'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Force update this channel only', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        'Only selected departments/people. Keep Default build lower so the rest of the factory is not forced.',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).appColors.textMuted),
                      ),
                      value: _inkForce,
                      activeThumbColor: kBrandOrange,
                      onChanged: (v) => setState(() => _inkForce = v),
                    ),
                  ],
                  const Divider(height: 28),
                  _channelHeader(
                    'People / pilot channel',
                    'Highest priority — select people and/or departments from lists',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled', style: TextStyle(fontSize: 14)),
                    value: _testersEnabled,
                    activeThumbColor: kBrandOrange,
                    onChanged: (v) => setState(() => _testersEnabled = v),
                  ),
                  if (_testersEnabled) ...[
                    _selectionSummary(
                      title: 'People',
                      chips: _employeeChipLabels(_testerClockNos),
                      emptyHint: 'No people selected.',
                      subtitle: 'From the full employee list (searchable).',
                      onEdit: () => _pickEmployees(
                        selectedClocks: _testerClockNos,
                        onSave: (s) => setState(() => _testerClockNos = s),
                      ),
                    ),
                    _selectionSummary(
                      title: 'Departments (optional)',
                      chips: _testerDepartments.toList()..sort(),
                      emptyHint: 'Optional whole departments on this pilot channel.',
                      onEdit: () => _pickDepartments(
                        selected: _testerDepartments,
                        onSave: (s) => setState(() => _testerDepartments = s),
                      ),
                    ),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _testersVersionController,
                          decoration: _inputDecoration('Version', hint: '2.4.0'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _testersBuildController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('Build', hint: '140'),
                        ),
                      ),
                    ]),
                    TextButton.icon(
                      onPressed: _fillTestersFromThisDevice,
                      icon: const Icon(Icons.phone_android, size: 18),
                      label: const Text('Fill from this device'),
                    ),
                    TextField(
                      controller: _testersUrlController,
                      decoration: _inputDecoration('Channel APK URL (optional)', hint: 'Empty = shared URL'),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _testersNotesController,
                      maxLines: 2,
                      decoration: _inputDecoration('Notes', hint: 'Dev only'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _testersShaController,
                      decoration: _inputDecoration('SHA-256 (optional)', hint: '64 hex'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Force update this channel', style: TextStyle(fontSize: 14)),
                      value: _testersForce,
                      activeThumbColor: kBrandOrange,
                      onChanged: (v) => setState(() => _testersForce = v),
                    ),
                  ],
                  const Divider(height: 28),
                  Text('Hard kill-switch (everyone)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).appColors.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _minBuildController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Min supported build', hint: 'Blocks ALL older builds at launch'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Checklist: (1) bump pubspec (2) CHANGELOG (3) host APK (4) set channel(s) (5) Save '
                    '(6) Copy RC only for Default if needed (7) min build only to retire broken APKs factory-wide. '
                    'Checks run every 24h; force re-blocks on resume.',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).appColors.textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyRemoteConfigSnippet,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copy RC keys'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveKillSwitch,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save publish'),
                        style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
                      ),
                    ),
                  ]),
                ]),
        ])),
    ]);
  }

  Widget _buildLocationBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('LOCATION'),
        _settingsCard(child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.map_outlined, color: kBrandOrange),
            title: const Text('Edit Geofence', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('Change site location and radius', style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GeofenceEditorScreen())),
          ),
          const Divider(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await LocationService().checkCurrentLocation();
                    if (mounted) _showSuccess('Location check completed');
                  } catch (e) { _showError('Error: $e'); }
                },
                icon: const Icon(Icons.location_on_outlined, size: 16),
                label: const Text('Force Check'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await LocationService().checkCurrentLocation();
                    if (mounted) _showSuccess('Simulated 30-min check completed');
                  } catch (e) { _showError('Error: $e'); }
                },
                icon: const Icon(Icons.timer_outlined, size: 16),
                label: const Text('Simulate 30min'),
              ),
            ),
          ]),
        ])),
    ]);
  }

  Widget _buildEscalationConfigSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Controls when unassigned jobs escalate and who gets notified at each stage.',
        style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
      ),
      const SizedBox(height: 12),
      _buildStageCard(stage: 1, subtitle: 'First escalation — job with no action', enabled: _stage1Enabled, onEnabledChanged: (v) => setState(() => _stage1Enabled = v), minutesController: _stage1MinController, selected: _stage1Recipients, onRecipientChanged: (r, v) => setState(() => v ? _stage1Recipients.add(r) : _stage1Recipients.remove(r))),
      const SizedBox(height: 8),
      _buildStageCard(stage: 2, subtitle: 'Second escalation — still unassigned after Stage 1', enabled: _stage2Enabled, onEnabledChanged: (v) => setState(() => _stage2Enabled = v), minutesController: _stage2MinController, selected: _stage2Recipients, onRecipientChanged: (r, v) => setState(() => v ? _stage2Recipients.add(r) : _stage2Recipients.remove(r))),
      const SizedBox(height: 8),
      _buildStageCard(stage: 3, subtitle: 'Third escalation — off-site managers', enabled: _stage3Enabled, onEnabledChanged: (v) => setState(() => _stage3Enabled = v), minutesController: _stage3MinController, selected: _stage3Recipients, onRecipientChanged: (r, v) => setState(() => v ? _stage3Recipients.add(r) : _stage3Recipients.remove(r))),
      const SizedBox(height: 8),
      _buildStageCard(stage: 4, subtitle: 'Final escalation stage', enabled: _stage4Enabled, onEnabledChanged: (v) => setState(() => _stage4Enabled = v), minutesController: _stage4MinController, selected: _stage4Recipients, onRecipientChanged: (r, v) => setState(() => v ? _stage4Recipients.add(r) : _stage4Recipients.remove(r))),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _saveNotificationConfig,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Escalation Config'),
          style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _clearEscalationStamps,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Reset Escalation Stamps'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red[700], side: BorderSide(color: Colors.red[700]!), padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      ),
    ]);
  }

  Widget _buildStageCard({
    required int stage,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required TextEditingController minutesController,
    required Set<String> selected,
    required void Function(String, bool) onRecipientChanged,
  }) {
    final colors = Theme.of(context).appColors;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: enabled ? kBrandOrange.withValues(alpha: 0.3) : colors.inputFill),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Stage $stage', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: colors.textMuted)),
            ])),
            Switch(value: enabled, onChanged: onEnabledChanged, activeThumbColor: kBrandOrange, activeTrackColor: kBrandOrange.withValues(alpha: 0.4)),
          ]),
          if (enabled) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 170,
              child: TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: _inputDecoration('Trigger after (minutes)'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Who gets notified', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textMuted)),
            ..._allRules.map((rule) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(_ruleLabels[rule] ?? rule, style: const TextStyle(fontSize: 13)),
              value: selected.contains(rule),
              activeColor: kBrandOrange, // ignore: deprecated_member_use
              onChanged: (v) => onRecipientChanged(rule, v ?? false),
            )),
          ],
        ]),
      ),
    );
  }
  // ── Comms tab ─────────────────────────────────────────────────────────────

  Widget _buildCommsTab() {
    final colors = Theme.of(context).appColors;
    return SingleChildScrollView(
      padding: ScreenInsets.symmetricScroll(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        _sectionHeader('BROADCAST MESSAGE'),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.campaign_outlined, color: kBrandOrange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sends a push notification to every employee\'s device. '
                'Off-site employees also receive an inbox item so the message persists until they return.',
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _broadcastTitleController,
            decoration: _inputDecoration('Notification title'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _broadcastBodyController,
            maxLines: 3,
            decoration: _inputDecoration('Message body'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isBroadcasting ? null : _sendBroadcast,
              icon: _isBroadcasting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
              label: Text(_isBroadcasting ? 'Sending…' : 'Send to All Employees'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kBrandOrange.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_lastBroadcastResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.wasteGreenSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.wasteGreen.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: colors.wasteGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sent to ${_lastBroadcastResult!['sent']} device${_lastBroadcastResult!['sent'] == 1 ? '' : 's'} · '
                    '${_lastBroadcastResult!['parked']} inbox items parked · '
                    '${_lastBroadcastResult!['noToken']} no token',
                    style: TextStyle(fontSize: 12, color: colors.wasteGreenDark),
                  ),
                ),
              ]),
            ),
          ],
        ])),

        const SizedBox(height: 16),
        _sectionHeader('TARGETED MESSAGE'),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Send the title and body above to specific employees by clock number. '
            'Useful for permission fix reminders or individual follow-ups.',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetedClockNosController,
            maxLines: 3,
            decoration: _inputDecoration(
              'Clock numbers (comma or newline separated)',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTargetedBroadcasting ? null : _sendTargetedBroadcast,
              icon: _isTargetedBroadcasting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_search_outlined),
              label: Text(_isTargetedBroadcasting ? 'Sending…' : 'Send to Selected'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D5A80),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF3D5A80).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_lastTargetedBroadcastResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.wasteGreenSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.wasteGreen.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: colors.wasteGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Targeted: sent to ${_lastTargetedBroadcastResult!['sent']} · '
                    '${_lastTargetedBroadcastResult!['parked']} inbox · '
                    '${_lastTargetedBroadcastResult!['noToken']} no token',
                    style: TextStyle(fontSize: 12, color: colors.wasteGreenDark),
                  ),
                ),
              ]),
            ),
          ],
        ])),

        const SizedBox(height: 4),
        _sectionHeader('RECENT BROADCASTS'),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('triggeredBy', isEqualTo: 'update_notice')
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
            }
            final docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? [])
              ..sort((a, b) {
                final aTs = (a.data() as Map)['createdAt'];
                final bTs = (b.data() as Map)['createdAt'];
                if (aTs is Timestamp && bTs is Timestamp) return bTs.compareTo(aTs);
                return 0;
              });
            final recent = docs.take(10).toList();

            if (recent.isEmpty) {
              return _settingsCard(child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No broadcasts sent yet', style: TextStyle(color: colors.textMuted, fontSize: 13)),
                ),
              ));
            }

            return Column(
              children: recent.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = data['createdAt'];
                DateTime? dt;
                if (ts is Timestamp) dt = ts.toDate();
                final sentCount = (data['sentTo'] as List?)?.length ?? 0;
                final scope = data['broadcastScope'] as String? ?? 'all';
                final sentBy = data['initiatedByName'] as String? ?? data['initiatedByClockNo'] as String? ?? '—';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colors.cardSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: kBrandOrange.withValues(alpha: 0.12),
                      child: const Icon(Icons.campaign_outlined, size: 18, color: kBrandOrange),
                    ),
                    title: Text(
                      data['title'] as String? ?? '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        data['body'] as String? ?? '',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'By $sentBy · $sentCount sent (${scope == 'targeted' ? 'targeted' : 'all'})',
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                    ]),
                    trailing: dt != null
                        ? Text(
                            '${dt.day}/${dt.month}\n${dt.year}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: colors.textMuted),
                          )
                        : null,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ]),
    );
  }
}
