import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

import '../stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/firestore_service.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import 'copper_dashboard_screen.dart';
import 'geofence_editor_screen.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Data-table source (unchanged — keeps the Job Cards tab paginated)
// ---------------------------------------------------------------------------

class JobCardsDataTableSource extends DataTableSource {
  final List<JobCard> jobCards;
  final Set<int> selectedRows;
  final int? editingIndex;
  final Function(int) onSelectChanged;
  final Function(int) onEditToggle;
  final Function(JobCard) onDelete;
  final TextEditingController priorityController;
  final TextEditingController statusController;
  final TextEditingController descriptionController;

  JobCardsDataTableSource({
    required this.jobCards,
    required this.selectedRows,
    required this.editingIndex,
    required this.onSelectChanged,
    required this.onEditToggle,
    required this.onDelete,
    required this.priorityController,
    required this.statusController,
    required this.descriptionController,
  });

  static Color _getPriorityColor(int p) {
    switch (p) {
      case 1: return const Color(0xFF2E7D32);
      case 2: return const Color(0xFF33691E);
      case 3: return const Color(0xFFBF360C);
      case 4: return const Color(0xFFC62828);
      case 5: return const Color(0xFFB71C1C);
      default: return Colors.grey;
    }
  }

  static Color _getStatusColor(JobStatus s) {
    switch (s) {
      case JobStatus.open: return const Color(0xFF1565C0);
      case JobStatus.inProgress: return const Color(0xFFE65100);
      case JobStatus.monitor: return Colors.orange;
      case JobStatus.closed: return const Color(0xFF2E7D32);
    }
  }

  @override
  DataRow getRow(int index) {
    final jc = jobCards[index];
    final isEditing = editingIndex == index;
    return DataRow(
      selected: selectedRows.contains(index),
      onSelectChanged: (selected) => onSelectChanged(index),
      cells: [
        DataCell(Checkbox(value: selectedRows.contains(index), onChanged: (v) => onSelectChanged(index))),
        DataCell(Text(jc.jobCardNumber?.toString() ?? '')),
        DataCell(isEditing
            ? DropdownButton<int>(
                value: jc.priority,
                items: [1, 2, 3, 4, 5].map((p) => DropdownMenuItem(value: p, child: Text('P$p'))).toList(),
                onChanged: (v) => priorityController.text = v.toString())
            : Chip(
                label: Text('P${jc.priority}', style: TextStyle(color: onColor(_getPriorityColor(jc.priority)), fontSize: 12)),
                backgroundColor: _getPriorityColor(jc.priority),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )),
        DataCell(isEditing
            ? DropdownButton<JobStatus>(
                value: jc.status,
                items: JobStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.displayName))).toList(),
                onChanged: (v) => statusController.text = v?.name ?? '')
            : Chip(
                label: Text(jc.status.displayName, style: TextStyle(color: onColor(_getStatusColor(jc.status)), fontSize: 12)),
                backgroundColor: _getStatusColor(jc.status),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )),
        DataCell(Text(jc.type.displayName)),
        DataCell(Text('${jc.department} › ${jc.area} › ${jc.machine}')),
        DataCell(isEditing
            ? TextField(controller: descriptionController)
            : Text(jc.description.length > 50 ? '${jc.description.substring(0, 50)}…' : jc.description)),
        DataCell(Text(jc.operator)),
        DataCell(Text(jc.assignedClockNos?.length.toString() ?? '0')),
        DataCell(Row(children: [
          IconButton(icon: Icon(isEditing ? Icons.save : Icons.edit, size: 18), onPressed: () => onEditToggle(index)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => onDelete(jc)),
        ])),
      ],
    );
  }

  @override int get rowCount => jobCards.length;
  @override bool get isRowCountApproximate => false;
  @override int get selectedRowCount => selectedRows.length;
}

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
  List<Employee> _filteredEmployees = [];

  // ── Structures ─────────────────────────────────────────────────────────────
  final TextEditingController deptController = TextEditingController();
  final TextEditingController areaController = TextEditingController();
  final TextEditingController machineController = TextEditingController();
  final TextEditingController structureSearchController = TextEditingController();
  String? selectedDeptForArea;
  String? selectedDeptForMachine;
  String? selectedAreaForMachine;
  Map<String, dynamic> _structure = {};

  // ── Settings — kill-switch ──────────────────────────────────────────────────
  final TextEditingController _minBuildController = TextEditingController();
  final TextEditingController _updateUrlController = TextEditingController();
  bool _killSwitchLoading = true;
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

  // ── Employees spreadsheet inline-edit ─────────────────────────────────────
  final Set<int> _selectedRows = {};
  int? _editingIndex;
  final TextEditingController _clockNoController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _fcmController = TextEditingController();

  // ── Job Cards tab ─────────────────────────────────────────────────────────
  final TextEditingController _jobCardSearchController = TextEditingController();
  // Paginated state — 50 records per page, cursor-based "Load More"
  List<JobCard> _jobCardPage = [];
  DocumentSnapshot? _lastJobCardDoc;
  bool _jobCardLoadingMore = false;
  bool _jobCardHasMore = true;
  bool _jobCardsLoaded = false;
  JobStatus? _jobCardStatusFilter;      // client-side chip filter on current page
  int? _editingJobCardIndex;
  final TextEditingController _jobCardPriorityController = TextEditingController();
  final TextEditingController _jobCardStatusController = TextEditingController();
  final TextEditingController _jobCardDescriptionController = TextEditingController();
  final Set<int> _selectedJobCardRows = {};

  // ── Comms tab ─────────────────────────────────────────────────────────────
  final TextEditingController _broadcastTitleController = TextEditingController(
    text: 'Update required — CTP Job Cards',
  );
  final TextEditingController _broadcastBodyController = TextEditingController(
    text: 'A required app update is available. Open the app and tap Update Now to install it.',
  );
  bool _isBroadcasting = false;
  Map<String, dynamic>? _lastBroadcastResult;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadStructure();
    _loadKillSwitch();
    _loadNotificationConfig();
    _loadCurrentClockNo();
    // Employees tab (index 0) loads eagerly — it's the landing tab.
    // Job Cards tab (index 3) loads lazily on first visit to avoid
    // downloading 1000 docs on every admin screen open.
    _loadEmployees();
  }

  void _onTabChanged() {
    setState(() {});
    if (_tabController.index == 3 && !_jobCardsLoaded) {
      _jobCardsLoaded = true;
      _fetchJobCardsPage(reset: true);
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
    _stage1MinController.dispose();
    _stage2MinController.dispose();
    _stage3MinController.dispose();
    _stage4MinController.dispose();
    _clockNoController.dispose();
    _nameController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _fcmController.dispose();
    _jobCardSearchController.dispose();
    _jobCardPriorityController.dispose();
    _jobCardStatusController.dispose();
    _jobCardDescriptionController.dispose();
    _broadcastTitleController.dispose();
    _broadcastBodyController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    setState(() {});
  }

  Future<void> _loadEmployees() async {
    try {
      _allEmployees = await _firestoreService.getAllEmployees();
      _filterEmployees();
    } catch (e) {
      _showError('Error loading employees: $e');
    }
  }

  void _filterEmployees() {
    final q = _employeeSearchController.text.toLowerCase();
    setState(() {
      _filteredEmployees = _allEmployees.where((e) =>
        e.name.toLowerCase().contains(q) ||
        e.department.toLowerCase().contains(q) ||
        e.position.toLowerCase().contains(q) ||
        e.clockNo.toLowerCase().contains(q),
      ).toList();
    });
  }

  /// Fetches the next page of job cards (newest first, 50 per page).
  /// Pass [reset] = true to restart from the beginning (e.g. after a delete).
  Future<void> _fetchJobCardsPage({bool reset = false}) async {
    if (!reset && (!_jobCardHasMore || _jobCardLoadingMore)) return;
    setState(() {
      _jobCardLoadingMore = true;
      if (reset) {
        _jobCardPage = [];
        _lastJobCardDoc = null;
        _jobCardHasMore = true;
        _selectedJobCardRows.clear();
        _editingJobCardIndex = null;
      }
    });
    try {
      final result = await _firestoreService.fetchAdminJobCardsPage(
        startAfter: reset ? null : _lastJobCardDoc,
      );
      setState(() {
        _jobCardPage = reset ? result.cards : [..._jobCardPage, ...result.cards];
        _lastJobCardDoc = result.lastDoc;
        _jobCardHasMore = result.hasMore;
        _jobCardLoadingMore = false;
      });
    } catch (e) {
      setState(() => _jobCardLoadingMore = false);
      _showError('Error loading job cards: $e');
    }
  }

  /// Client-side filter applied on top of the current page.
  List<JobCard> get _displayedJobCards {
    final q = _jobCardSearchController.text.toLowerCase();
    return _jobCardPage.where((jc) {
      if (_jobCardStatusFilter != null && jc.status != _jobCardStatusFilter) return false;
      if (q.isEmpty) return true;
      return jc.description.toLowerCase().contains(q) ||
             jc.operator.toLowerCase().contains(q) ||
             jc.machine.toLowerCase().contains(q) ||
             (jc.jobCardNumber?.toString() ?? '').contains(q);
    }).toList();
  }

  Future<void> _loadStructure() async {
    try {
      _structure = _normalizeStructure(await _firestoreService.getFactoryStructure());
      setState(() {});
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
      setState(() {
        _minBuildController.text = (data['minSupportedBuild'] ?? '').toString();
        _updateUrlController.text = (data['updateDownloadUrl'] ?? '').toString();
        _killSwitchLoading = false;
      });
    } catch (_) {
      setState(() => _killSwitchLoading = false);
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
    final build = int.tryParse(_minBuildController.text.trim());
    if (_minBuildController.text.trim().isNotEmpty && build == null) {
      _showError('Min supported build must be a whole number');
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('settings').doc('app').set({
        if (build != null) 'minSupportedBuild': build,
        if (_updateUrlController.text.trim().isNotEmpty)
          'updateDownloadUrl': _updateUrlController.text.trim(),
      }, SetOptions(merge: true));
      if (mounted) _showSuccess('Kill-switch settings saved');
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
        },
        'excluded_job_types': ['maintenance', 'building', 'specialist'],
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
      final result = await FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('clearEscalationStamps')
          .call();
      if (mounted) _showSuccess('Cleared stamps from ${result.data['cleared'] ?? 0} job cards');
    } catch (e) {
      _showError('Error: $e');
    }
  }

  Future<void> _sendBroadcast() async {
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

  // ── Employee CRUD ─────────────────────────────────────────────────────────

  void _toggleEdit(int index) {
    if (_editingIndex == index) {
      final emp = _allEmployees[index];
      _firestoreService.updateEmployee(emp.copyWith(
        clockNo: _clockNoController.text,
        name: _nameController.text,
        position: _positionController.text,
        department: _departmentController.text,
        fcmToken: _fcmController.text.isEmpty ? null : _fcmController.text,
      ));
      _editingIndex = null;
    } else {
      _editingIndex = index;
      final emp = _allEmployees[index];
      _clockNoController.text = emp.clockNo;
      _nameController.text = emp.name;
      _positionController.text = emp.position;
      _departmentController.text = emp.department;
      _fcmController.text = emp.fcmToken ?? '';
    }
    setState(() {});
  }

  void _bulkDelete() async {
    for (final i in _selectedRows) {
      await _firestoreService.deleteEmployee(_allEmployees[i].clockNo);
    }
    _selectedRows.clear();
    setState(() {});
  }

  void _deleteEmployee(String clockNo) async {
    final ok = await _confirmDialog('Delete Employee', 'Are you sure?');
    if (!ok) return;
    try {
      await _firestoreService.deleteEmployee(clockNo);
      _loadEmployees();
      if (mounted) _showSuccess('Employee deleted');
    } catch (e) { _showError('Error: $e'); }
  }

  void _showEmployeeDialog([Employee? employee]) {
    final isEdit = employee != null;
    final cnCtrl = TextEditingController(text: employee?.clockNo ?? '');
    final nameCtrl = TextEditingController(text: employee?.name ?? '');
    final posCtrl = TextEditingController(text: employee?.position ?? '');
    final deptCtrl = TextEditingController(text: employee?.department ?? '');
    final fcmCtrl = TextEditingController(text: employee?.fcmToken ?? '');
    bool isOnSite = employee?.isOnSite ?? true;

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
                    fcmTokenUpdatedAt: employee?.fcmTokenUpdatedAt,
                  );
                  if (isEdit) { await _firestoreService.updateEmployee(emp); } else { await _firestoreService.createEmployee(emp); }
                  nav.pop();
                  _loadEmployees();
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
    _structure.remove(dept);
    await _firestoreService.updateFactoryStructure(_structure);
    setState(() {});
  }

  void _deleteArea(String dept, String area) async {
    final ok = await _confirmDialog('Delete Area', 'This deletes all machines in $area.');
    if (!ok) return;
    (_structure[dept] as Map).remove(area);
    await _firestoreService.updateFactoryStructure(_structure);
    setState(() {});
  }

  void _deleteMachine(String dept, String area, String machine) async {
    final ok = await _confirmDialog('Delete Machine', 'Remove $machine?');
    if (!ok) return;
    (_structure[dept][area] as List).remove(machine);
    await _firestoreService.updateFactoryStructure(_structure);
    setState(() {});
  }

  // ── Job Card CRUD ─────────────────────────────────────────────────────────

  void _toggleJobCardEdit(int index) {
    final displayed = _displayedJobCards;
    if (_editingJobCardIndex == index) {
      final jc = displayed[index];
      _firestoreService.updateJobCard(jc.id!, jc.copyWith(
        priority: int.tryParse(_jobCardPriorityController.text) ?? jc.priority,
        status: JobStatusExtension.fromString(_jobCardStatusController.text),
        description: _jobCardDescriptionController.text,
      ));
      _editingJobCardIndex = null;
    } else {
      _editingJobCardIndex = index;
      final jc = displayed[index];
      _jobCardPriorityController.text = jc.priority.toString();
      _jobCardStatusController.text = jc.status.name;
      _jobCardDescriptionController.text = jc.description;
    }
    setState(() {});
  }

  void _deleteJobCard(JobCard jc) async {
    final ok = await _confirmDialog('Delete Job Card', '#${jc.jobCardNumber} — ${jc.description.substring(0, jc.description.length.clamp(0, 60))}');
    if (!ok) return;
    try {
      await _firestoreService.deleteJobCard(jc.id!);
      _fetchJobCardsPage(reset: true);
      if (mounted) _showSuccess('Job card deleted');
    } catch (e) { _showError('Error: $e'); }
  }

  void _bulkDeleteJobCards() async {
    final displayed = _displayedJobCards;
    for (final i in _selectedJobCardRows) {
      if (i < displayed.length) {
        await _firestoreService.deleteJobCard(displayed[i].id!);
      }
    }
    _fetchJobCardsPage(reset: true);
  }

  // ── CSV ────────────────────────────────────────────────────────────────────

  void _exportTemplate() {
    final csv = Csv().encode([
      ['clockNo', 'name', 'position', 'department', 'isOnSite', 'fcmToken'],
      ['', '', '', '', 'true', ''],
    ]);
    _shareOrDownload(csv, 'employees_template.csv');
  }

  void _exportJobCardsCsv() {
    // Exports the currently loaded page (up to 50 records per page).
    // Use "Load More" to accumulate more records before exporting.
    final rows = _displayedJobCards;
    final csv = Csv().encode([
      ['Job #', 'Priority', 'Status', 'Type', 'Department', 'Area', 'Machine', 'Part', 'Description', 'Operator', 'Assigned', 'Created'],
      ...rows.map((jc) => [
        jc.jobCardNumber?.toString() ?? '', jc.priority.toString(), jc.status.displayName,
        jc.type.displayName, jc.department, jc.area, jc.machine, jc.part, jc.description,
        jc.operator, jc.assignedClockNos?.length.toString() ?? '0', jc.createdAt?.toString() ?? '',
      ]),
    ]);
    _shareOrDownload(csv, 'job_cards_${rows.length}.csv');
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
        title: const Text('Admin'),
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
            Tab(icon: Icon(Icons.people_outline, size: 18), text: 'Employees'),
            Tab(icon: Icon(Icons.account_tree_outlined, size: 18), text: 'Structures'),
            Tab(icon: Icon(Icons.tune, size: 18), text: 'Settings'),
            Tab(icon: Icon(Icons.assignment_outlined, size: 18), text: 'Job Cards'),
            Tab(icon: Icon(Icons.location_on_outlined, size: 18), text: 'On Site'),
            Tab(icon: Icon(Icons.campaign_outlined, size: 18), text: 'Comms'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmployeesTab(),
          _buildStructuresTab(),
          _buildSettingsTab(),
          _buildJobCardsTab(),
          _buildOnsiteTab(),
          _buildCommsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _showEmployeeDialog,
              backgroundColor: kBrandOrange,
              child: const Icon(Icons.person_add_outlined, color: Colors.white),
            )
          : null,
    );
  }

  // ── On Site tab ───────────────────────────────────────────────────────────

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
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          grouped.putIfAbsent((data['department'] as String? ?? 'Unknown').trim(), () => []).add({...data, 'id': doc.id});
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
                          backgroundColor: colors.wasteGreenSurface,
                          child: Text(
                            (emp['name'] as String? ?? '?')[0].toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold, color: colors.wasteGreenDark),
                          ),
                        ),
                        title: Text(emp['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(emp['position'] as String? ?? '—', style: TextStyle(fontSize: 12, color: colors.textMuted)),
                        trailing: Text(
                          emp['id'] as String? ?? '',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colors.textMuted),
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

  Widget _buildEmployeesTab() {
    final colors = Theme.of(context).appColors;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _employeeSearchController,
              decoration: _inputDecoration('Search employees', hint: 'Name, clock no, department…'),
              onChanged: (_) => _filterEmployees(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _exportTemplate, icon: const Icon(Icons.download, size: 16), label: const Text('Template')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _importCsv, icon: const Icon(Icons.upload, size: 16), label: const Text('Import')),
          if (_selectedRows.isNotEmpty) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _bulkDelete,
              icon: const Icon(Icons.delete, size: 16),
              label: Text('Delete ${_selectedRows.length}'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            ),
          ],
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Employee>>(
          stream: _firestoreService.getEmployeesStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && _allEmployees.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final employees = snapshot.data ?? _allEmployees;
            _allEmployees = employees;
            _filterEmployees();
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  headingRowColor: WidgetStateProperty.all(colors.inputFill),
                  columns: const [
                    DataColumn(label: Text('', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('Clock No', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('Name', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('Position', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('Department', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('On Site', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('FCM Token', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontSize: 12))),
                  ],
                  rows: _filteredEmployees.map((emp) {
                    final index = _allEmployees.indexOf(emp);
                    final isEditing = _editingIndex == index;
                    return DataRow(
                      selected: _selectedRows.contains(index),
                      onSelectChanged: (v) => setState(() => v! ? _selectedRows.add(index) : _selectedRows.remove(index)),
                      cells: [
                        DataCell(Checkbox(value: _selectedRows.contains(index), onChanged: (v) => setState(() => v! ? _selectedRows.add(index) : _selectedRows.remove(index)))),
                        DataCell(isEditing ? SizedBox(width: 70, child: TextField(controller: _clockNoController, style: const TextStyle(fontSize: 13))) : Text(emp.clockNo, style: const TextStyle(fontSize: 13))),
                        DataCell(isEditing ? SizedBox(width: 120, child: TextField(controller: _nameController, style: const TextStyle(fontSize: 13))) : Text(emp.name, style: const TextStyle(fontSize: 13))),
                        DataCell(isEditing ? SizedBox(width: 120, child: TextField(controller: _positionController, style: const TextStyle(fontSize: 13))) : Text(emp.position, style: const TextStyle(fontSize: 13))),
                        DataCell(isEditing ? SizedBox(width: 120, child: TextField(controller: _departmentController, style: const TextStyle(fontSize: 13))) : Text(emp.department, style: const TextStyle(fontSize: 13))),
                        DataCell(
                          GestureDetector(
                            onTap: () => _firestoreService.updateEmployee(emp.copyWith(isOnSite: !emp.isOnSite)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: emp.isOnSite ? colors.wasteGreenSurface : colors.inputFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                emp.isOnSite ? 'On Site' : 'Off Site',
                                style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: emp.isOnSite ? colors.wasteGreenDark : colors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        DataCell(isEditing
                            ? SizedBox(width: 120, child: TextField(controller: _fcmController, style: const TextStyle(fontSize: 12)))
                            : SizedBox(width: 120, child: Text(
                                emp.fcmToken != null ? (emp.fcmToken!.length > 20 ? '${emp.fcmToken!.substring(0, 20)}…' : emp.fcmToken!) : '—',
                                style: TextStyle(fontSize: 11, color: colors.textMuted, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ))),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: Icon(isEditing ? Icons.save : Icons.edit_outlined, size: 16), onPressed: () => _toggleEdit(index), visualDensity: VisualDensity.compact),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _deleteEmployee(emp.clockNo), visualDensity: VisualDensity.compact),
                          IconButton(icon: const Icon(Icons.open_in_new, size: 16), onPressed: () => _showEmployeeDialog(emp), visualDensity: VisualDensity.compact),
                        ])),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── Structures tab ────────────────────────────────────────────────────────

  Widget _buildStructuresTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(
          controller: structureSearchController,
          decoration: _inputDecoration('Search structures', hint: 'Department, area, machine…'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(children: [
            _sectionHeader('CURRENT STRUCTURE'),
            ..._buildStructureList(),
            const SizedBox(height: 8),
            _sectionHeader('ADD DEPARTMENT'),
            TextField(controller: deptController, decoration: _inputDecoration('Department name')),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (deptController.text.trim().isEmpty) return;
                  final structure = await _firestoreService.getFactoryStructure();
                  structure[deptController.text.trim()] = {};
                  await _firestoreService.updateFactoryStructure(structure);
                  deptController.clear();
                  _loadStructure();
                  if (mounted) _showSuccess('Department added');
                },
                style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
                child: const Text('Add Department'),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('ADD AREA'),
            FutureBuilder<Map<String, dynamic>>(
              future: _firestoreService.getFactoryStructure(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: snap.data!.keys.map((dept) => ChoiceChip(
                      label: Text(dept, style: const TextStyle(fontSize: 12)),
                      selected: selectedDeptForArea == dept,
                      onSelected: (_) => setState(() => selectedDeptForArea = dept),
                      selectedColor: kBrandOrange,
                      labelStyle: TextStyle(color: selectedDeptForArea == dept ? Colors.white : Theme.of(context).appColors.chipUnselectedLabel),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: areaController, decoration: _inputDecoration('Area name')),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (selectedDeptForArea == null || areaController.text.trim().isEmpty) return;
                        final structure = await _firestoreService.getFactoryStructure();
                        (structure[selectedDeptForArea] as Map<String, dynamic>)[areaController.text.trim()] = [];
                        await _firestoreService.updateFactoryStructure(structure);
                        areaController.clear();
                        _loadStructure();
                        if (mounted) _showSuccess('Area added');
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
                      child: const Text('Add Area'),
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 16),
            _sectionHeader('ADD MACHINE / PART'),
            FutureBuilder<Map<String, dynamic>>(
              future: _firestoreService.getFactoryStructure(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final data = snap.data!;
                final areas = selectedDeptForMachine != null
                    ? (data[selectedDeptForMachine] as Map<String, dynamic>? ?? {}).keys.toList()
                    : <String>[];
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: data.keys.map((dept) => ChoiceChip(
                      label: Text(dept, style: const TextStyle(fontSize: 12)),
                      selected: selectedDeptForMachine == dept,
                      onSelected: (_) => setState(() { selectedDeptForMachine = dept; selectedAreaForMachine = null; }),
                      selectedColor: kBrandOrange,
                      labelStyle: TextStyle(color: selectedDeptForMachine == dept ? Colors.white : Theme.of(context).appColors.chipUnselectedLabel),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  if (selectedDeptForMachine != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: areas.map((area) => ChoiceChip(
                        label: Text(area, style: const TextStyle(fontSize: 12)),
                        selected: selectedAreaForMachine == area,
                        onSelected: (_) => setState(() => selectedAreaForMachine = area),
                        selectedColor: kBrandOrange,
                        labelStyle: TextStyle(color: selectedAreaForMachine == area ? Colors.white : Theme.of(context).appColors.chipUnselectedLabel),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(controller: machineController, decoration: _inputDecoration('Machine / Part name')),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (selectedDeptForMachine == null || selectedAreaForMachine == null || machineController.text.trim().isEmpty) return;
                        final structure = await _firestoreService.getFactoryStructure();
                        (structure[selectedDeptForMachine]![selectedAreaForMachine] as List<dynamic>).add(machineController.text.trim());
                        await _firestoreService.updateFactoryStructure(structure);
                        machineController.clear();
                        _loadStructure();
                        if (mounted) _showSuccess('Machine added');
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
                      child: const Text('Add Machine / Part'),
                    ),
                  ),
                ]);
              },
            ),
          ]),
        ),
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

    return filtered.entries.map((deptEntry) => ExpansionTile(
      title: Row(children: [
        Text(deptEntry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), onPressed: () => _deleteDepartment(deptEntry.key), visualDensity: VisualDensity.compact),
      ]),
      children: (deptEntry.value as Map<String, dynamic>).entries.map((areaEntry) => ExpansionTile(
        title: Row(children: [
          Text(areaEntry.key, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16), onPressed: () => _deleteArea(deptEntry.key, areaEntry.key), visualDensity: VisualDensity.compact),
        ]),
        children: (areaEntry.value as List).map((machine) => ListTile(
          dense: true,
          title: Text(machine.toString(), style: const TextStyle(fontSize: 13)),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16), onPressed: () => _deleteMachine(deptEntry.key, areaEntry.key, machine.toString()), visualDensity: VisualDensity.compact),
        )).toList(),
      )).toList(),
    )).toList();
  }

  // ── Settings tab ──────────────────────────────────────────────────────────

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── App Kill-switch ─────────────────────────────────────────────────
        _sectionHeader('APP UPDATE CONTROL'),
        _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.security_update_warning_outlined, color: kBrandOrange, size: 18),
            const SizedBox(width: 8),
            const Text('Force Update Gate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Set the minimum build number that the app accepts. Users on older builds see a blocking update screen until they upgrade.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
          ),
          const SizedBox(height: 12),
          _killSwitchLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _minBuildController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Min supported build', hint: 'e.g. 42'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _updateUrlController,
                    decoration: _inputDecoration('Update download URL', hint: 'https://…/app-release.apk'),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveKillSwitch,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange, foregroundColor: Colors.white),
                    ),
                  ),
                ]),
        ])),

        // ── Location ────────────────────────────────────────────────────────
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

        // ── Access ──────────────────────────────────────────────────────────
        _sectionHeader('ACCESS'),
        _settingsCard(child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined, color: kBrandOrange),
          title: const Text('Copper Storage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text('View and manage copper inventory', style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            if (_currentClockNo == '22') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CopperDashboardScreen()));
            } else {
              _showError('Admin access required');
            }
          },
        )),

        // ── Escalation ──────────────────────────────────────────────────────
        _sectionHeader('ESCALATION RULES'),
        _buildEscalationConfigSection(),
      ]),
    );
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

  // ── Job Cards tab ─────────────────────────────────────────────────────────

  Widget _buildJobCardsTab() {
    if (!_jobCardsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).appColors;
    final displayed = _displayedJobCards;

    return Column(children: [
      // ── Toolbar ────────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _jobCardSearchController,
              decoration: _inputDecoration('Search description, machine, operator, job #'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _exportJobCardsCsv,
            icon: const Icon(Icons.download, size: 16),
            label: Text('Export (${displayed.length})'),
          ),
          if (_selectedJobCardRows.isNotEmpty) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _bulkDeleteJobCards,
              icon: const Icon(Icons.delete, size: 16),
              label: Text('Delete ${_selectedJobCardRows.length}'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            ),
          ],
        ]),
      ),

      // ── Status filter chips ────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _statusChip(null, 'All'),
            const SizedBox(width: 6),
            _statusChip(JobStatus.open, 'Open'),
            const SizedBox(width: 6),
            _statusChip(JobStatus.inProgress, 'In Progress'),
            const SizedBox(width: 6),
            _statusChip(JobStatus.monitor, 'Monitor'),
            const SizedBox(width: 6),
            _statusChip(JobStatus.closed, 'Closed'),
            const SizedBox(width: 12),
            Text(
              '${_jobCardPage.length} loaded${_jobCardHasMore ? ' — more available' : ' (all)'}',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ]),
        ),
      ),

      // ── Data table ─────────────────────────────────────────────────────────
      Expanded(
        child: _jobCardLoadingMore && _jobCardPage.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(children: [
                  PaginatedDataTable(
                    header: Text('${displayed.length} shown', style: const TextStyle(fontSize: 14)),
                    rowsPerPage: 15,
                    headingRowColor: WidgetStateProperty.all(colors.inputFill),
                    columns: const [
                      DataColumn(label: Text('')),
                      DataColumn(label: Text('Job #')),
                      DataColumn(label: Text('Priority')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Location')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Operator')),
                      DataColumn(label: Text('Assigned')),
                      DataColumn(label: Text('Actions')),
                    ],
                    source: JobCardsDataTableSource(
                      jobCards: displayed,
                      selectedRows: _selectedJobCardRows,
                      editingIndex: _editingJobCardIndex,
                      onSelectChanged: (i) => setState(() =>
                          _selectedJobCardRows.contains(i)
                              ? _selectedJobCardRows.remove(i)
                              : _selectedJobCardRows.add(i)),
                      onEditToggle: _toggleJobCardEdit,
                      onDelete: _deleteJobCard,
                      priorityController: _jobCardPriorityController,
                      statusController: _jobCardStatusController,
                      descriptionController: _jobCardDescriptionController,
                    ),
                  ),

                  // ── Load More ───────────────────────────────────────────────
                  if (_jobCardHasMore || _jobCardLoadingMore)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _jobCardLoadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton.icon(
                              onPressed: () => _fetchJobCardsPage(),
                              icon: const Icon(Icons.expand_more, size: 18),
                              label: const Text('Load next 50'),
                            ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'All ${_jobCardPage.length} records loaded',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ),
                ]),
              ),
      ),
    ]);
  }

  Widget _statusChip(JobStatus? status, String label) {
    final selected = _jobCardStatusFilter == status;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() {
        _jobCardStatusFilter = status;
        _selectedJobCardRows.clear();
        _editingJobCardIndex = null;
      }),
      selectedColor: kBrandOrange.withValues(alpha: 0.2),
      checkmarkColor: kBrandOrange,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  // ── Comms tab ─────────────────────────────────────────────────────────────

  Widget _buildCommsTab() {
    final colors = Theme.of(context).appColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                        'By $sentBy · $sentCount sent',
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
