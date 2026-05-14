import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../stub.dart' if (dart.library.html) 'dart:html' as html;
import '../services/firestore_service.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import 'copper_dashboard_screen.dart';
import 'geofence_editor_screen.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

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
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.yellow;
      case 4: return Colors.lightGreen;
      case 5: return Colors.green;
      default: return Colors.grey;
    }
  }

  static Color _getStatusColor(JobStatus s) {
    switch (s) {
      case JobStatus.open: return Colors.blue;
      case JobStatus.inProgress: return Colors.purple;
      case JobStatus.monitor: return Colors.orange;
      case JobStatus.closed: return Colors.green;
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
        DataCell(isEditing ? DropdownButton<int>(value: jc.priority, items: [1,2,3,4,5].map((p) => DropdownMenuItem(value: p, child: Text('P$p'))).toList(), onChanged: (v) => priorityController.text = v.toString()) : Chip(label: Text('P${jc.priority}'), backgroundColor: _getPriorityColor(jc.priority))),
        DataCell(isEditing ? DropdownButton<JobStatus>(value: jc.status, items: JobStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.displayName))).toList(), onChanged: (v) => statusController.text = v?.name ?? '') : Chip(label: Text(jc.status.displayName), backgroundColor: _getStatusColor(jc.status))),
        DataCell(Text(jc.type.displayName)),
        DataCell(Text('${jc.department} > ${jc.area} > ${jc.machine} > ${jc.part}')),
        DataCell(isEditing ? TextField(controller: descriptionController) : Text(jc.description.length > 50 ? '${jc.description.substring(0,50)}...' : jc.description)),
        DataCell(Text(jc.operator)),
        DataCell(Text(jc.assignedClockNos?.length.toString() ?? '0')),
        DataCell(Row(children: [IconButton(icon: Icon(isEditing ? Icons.save : Icons.edit), onPressed: () => onEditToggle(index)), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => onDelete(jc))])),
      ],
    );
  }

  @override
  int get rowCount => jobCards.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => selectedRows.length;
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  // Employees tab
  final TextEditingController _employeeSearchController = TextEditingController();
  List<Employee> _allEmployees = [];
  List<Employee> _filteredEmployees = [];

  // Structures tab (keep old controllers)
  final TextEditingController deptController = TextEditingController();
  final TextEditingController areaController = TextEditingController();
  final TextEditingController machineController = TextEditingController();
  final TextEditingController structureSearchController = TextEditingController();

  String? selectedDeptForArea;
  String? selectedDeptForMachine;
  String? selectedAreaForMachine;
  Map<String, dynamic> _structure = {};

  // Settings tab
  final TextEditingController _passwordController = TextEditingController();
  String _currentPassword = '';
  String? _currentClockNo;

  // Notification escalation config
  final TextEditingController _shortMinController = TextEditingController(text: '2');
  final TextEditingController _longMinController = TextEditingController(text: '7');
  final TextEditingController _offsiteMinController = TextEditingController(text: '30');
  final TextEditingController _stage4MinController = TextEditingController(text: '60');
  static const _allRules = [
    'onsite_managers',
    'foremen',
    'onsite_dept_managers',
    'onsite_workshop_manager',
    'onsite_mechanics',
    'onsite_electricians',
    'offsite_managers',
    'offsite_dept_managers',
    'offsite_workshop_manager',
  ];
  static const _ruleLabels = {
    'onsite_managers': 'On-site Mech/Elec Manager (by job type)',
    'foremen': 'On-site Foreman / Shift Leader',
    'onsite_dept_managers': 'On-site Department Manager',
    'onsite_workshop_manager': 'On-site Workshop Manager',
    'onsite_mechanics': 'On-site Mechanics',
    'onsite_electricians': 'On-site Electricians',
    'offsite_managers': 'Off-site Mech/Elec Manager (by job type)',
    'offsite_dept_managers': 'Off-site Department Manager',
    'offsite_workshop_manager': 'Off-site Workshop Manager',
  };
  Set<String> _stage1Recipients = {'onsite_managers', 'foremen'};
  Set<String> _stage2Recipients = {'onsite_dept_managers', 'onsite_workshop_manager'};
  Set<String> _stage3Recipients = {};
  Set<String> _stage4Recipients = {};

  // Spreadsheet state
  final Set<int> _selectedRows = {};
  int? _editingIndex;
  final TextEditingController _clockNoController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _fcmController = TextEditingController();

  // Job Cards tab
  final TextEditingController _jobCardSearchController = TextEditingController();
  List<JobCard> _allJobCards = [];
  List<JobCard> _filteredJobCards = [];
  String? _selectedOperator;
  int? _editingJobCardIndex;
  final TextEditingController _jobCardPriorityController = TextEditingController();
  final TextEditingController _jobCardStatusController = TextEditingController();
  final TextEditingController _jobCardDescriptionController = TextEditingController();
  final Set<int> _selectedJobCardRows = {};

  @override
  void initState() {
    super.initState();
    debugPrint('AdminScreen initState'); // Debug
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _loadEmployees();
    _loadStructure();
    _loadSettings();
    _loadNotificationConfig();
    _loadCurrentClockNo();
    _loadJobCards();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _employeeSearchController.dispose();
    deptController.dispose();
    areaController.dispose();
    machineController.dispose();
    structureSearchController.dispose();
    _passwordController.dispose();
    _shortMinController.dispose();
    _longMinController.dispose();
    _offsiteMinController.dispose();
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
    super.dispose();
  }

  Map<String, dynamic> _normalizeStructure(Map<String, dynamic> structure) {
    final normalized = <String, dynamic>{};
    structure.forEach((dept, areas) {
      if (areas is Map) {
        final normalizedAreas = <String, dynamic>{};
        (areas as Map<String, dynamic>).forEach((area, machines) {
          if (machines is List) {
            normalizedAreas[area] = machines;
          } else if (machines is String) {
            normalizedAreas[area] = [machines];
          } else {
            normalizedAreas[area] = [];
          }
        });
        normalized[dept] = normalizedAreas;
      } else {
        normalized[dept] = {};
      }
    });
    return normalized;
  }

  Future<void> _loadEmployees() async {
    try {
      _allEmployees = await _firestoreService.getAllEmployees();
      _filterEmployees();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading employees: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterEmployees() {
    final query = _employeeSearchController.text.toLowerCase();
    _filteredEmployees = _allEmployees.where((emp) =>
      emp.name.toLowerCase().contains(query) ||
      emp.department.toLowerCase().contains(query) ||
      emp.position.toLowerCase().contains(query) ||
      emp.clockNo.toLowerCase().contains(query)
    ).toList();
  }

  Future<void> _loadJobCards() async {
    try {
      _allJobCards = await _firestoreService.getAllJobCardsFuture();
      _filterJobCards();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading job cards: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterJobCards() {
    final query = _jobCardSearchController.text.toLowerCase();
    _filteredJobCards = _allJobCards.where((jc) =>
      jc.description.toLowerCase().contains(query) ||
      jc.comments.toLowerCase().contains(query) ||
      jc.notes.toLowerCase().contains(query)
    ).where((jc) => _selectedOperator == null || jc.operator == _selectedOperator).toList();
  }

  Future<void> _loadStructure() async {
    try {
      _structure = _normalizeStructure(await _firestoreService.getFactoryStructure());
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading structure: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      _currentPassword = await _firestoreService.getSwitchUserPassword();
      _passwordController.text = _currentPassword;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadNotificationConfig() async {
    try {
      final config = await _firestoreService.getNotificationConfig();
      setState(() {
        _shortMinController.text = (config['escalation_onsite_short_minutes'] ?? 2).toString();
        _longMinController.text = (config['escalation_onsite_long_minutes'] ?? 7).toString();
        _offsiteMinController.text = (config['escalation_offsite_minutes'] ?? 30).toString();
        _stage4MinController.text = (config['escalation_stage4_minutes'] ?? 60).toString();
        _stage1Recipients = Set<String>.from((config['stage1_recipients'] as List? ?? ['onsite_managers', 'foremen']));
        _stage2Recipients = Set<String>.from((config['stage2_recipients'] as List? ?? ['onsite_dept_managers', 'onsite_workshop_manager']));
        _stage3Recipients = Set<String>.from((config['stage3_recipients'] as List? ?? []));
        _stage4Recipients = Set<String>.from((config['stage4_recipients'] as List? ?? []));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notification config: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveNotificationConfig() async {
    final short = int.tryParse(_shortMinController.text) ?? 2;
    final long = int.tryParse(_longMinController.text) ?? 7;
    final offsite = int.tryParse(_offsiteMinController.text) ?? 30;
    final stage4 = int.tryParse(_stage4MinController.text) ?? 60;

    if (short >= long) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stage 1 minutes must be less than Stage 2 minutes'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await _firestoreService.saveNotificationConfig({
        'escalation_onsite_short_minutes': short,
        'escalation_onsite_long_minutes': long,
        'escalation_offsite_minutes': offsite,
        'escalation_stage4_minutes': stage4,
        'stage1_recipients': _stage1Recipients.toList(),
        'stage2_recipients': _stage2Recipients.toList(),
        'stage3_recipients': _stage3Recipients.toList(),
        'stage4_recipients': _stage4Recipients.toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escalation config saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving config: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    debugPrint('Debug: Loaded ClockNo: $_currentClockNo'); // Debug
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Manage Collections'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Employees'),
            Tab(text: 'Structures'),
            Tab(text: 'Settings'),
            Tab(text: 'Job Cards'),
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
        ],
      ),
      floatingActionButton: (_tabController.index == 0 || _tabController.index == 3) ? FloatingActionButton(
        onPressed: () => _tabController.index == 0 ? _showEmployeeDialog() : null, // No add for job cards yet
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Widget _buildEmployeesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _employeeSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search Employees',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() => _filterEmployees()),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _exportTemplate,
                icon: const Icon(Icons.download),
                label: const Text('Export Template'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload),
                label: const Text('Import CSV'),
              ),
              if (_selectedRows.isNotEmpty) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _bulkDelete,
                  icon: const Icon(Icons.delete, color: Colors.white),
                  label: const Text('Delete Selected'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Employee>>(
            stream: _firestoreService.getEmployeesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && _allEmployees.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final employees = snapshot.data ?? _allEmployees;
              _allEmployees = employees;
              _filterEmployees();
              return SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Select')),
                      DataColumn(label: Text('Clock No')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Position')),
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('On Site')),
                      DataColumn(label: Text('FCM Token')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: _filteredEmployees.map((emp) {
                      final index = _allEmployees.indexOf(emp);
                      final isEditing = _editingIndex == index;
                      return DataRow(
                        selected: _selectedRows.contains(index),
                        onSelectChanged: (selected) {
                          if (selected!) {
                            _selectedRows.add(index);
                          } else {
                            _selectedRows.remove(index);
                          }
                          setState(() {});
                        },
                        cells: [
                          DataCell(
                            Checkbox(
                              value: _selectedRows.contains(index),
                              onChanged: (v) {
                                if (v!) {
                                  _selectedRows.add(index);
                                } else {
                                  _selectedRows.remove(index);
                                }
                                setState(() {});
                              },
                            ),
                          ),
                          DataCell(isEditing ? TextField(controller: _clockNoController) : Text(emp.clockNo)),
                          DataCell(isEditing ? TextField(controller: _nameController) : Text(emp.name)),
                          DataCell(isEditing ? TextField(controller: _positionController) : Text(emp.position)),
                          DataCell(isEditing ? TextField(controller: _departmentController) : Text(emp.department)),
                          DataCell(
                            Checkbox(
                              value: emp.isOnSite,
                              onChanged: (v) => _firestoreService.updateEmployee(emp.copyWith(isOnSite: v ?? true)),
                            ),
                          ),
                          DataCell(isEditing ? SizedBox(width: 150, child: TextField(controller: _fcmController)) : SizedBox(width: 150, child: Text(emp.fcmToken != null ? (emp.fcmToken!.length > 100 ? '${emp.fcmToken!.substring(0, 100)}...' : emp.fcmToken!) : '', overflow: TextOverflow.ellipsis))),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(isEditing ? Icons.save : Icons.edit),
                                  onPressed: () => _toggleEdit(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteEmployee(emp.clockNo),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStructuresTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: structureSearchController,
            decoration: const InputDecoration(
              labelText: 'Search Structures',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                const Text('Current Structure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ..._buildStructureList(),
                const Divider(height: 20),
                const Text('Add New Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextField(
                  controller: deptController,
                  decoration: const InputDecoration(labelText: 'Department name'),
                ),
                ElevatedButton(
                          onPressed: () async {
                            if (!mounted) return;
                            try {
                              final structure = await _firestoreService.getFactoryStructure();
                              (structure[selectedDeptForArea] as Map<String, dynamic>)[areaController.text] = [];
                              await _firestoreService.updateFactoryStructure(structure);
                              areaController.clear();
                              _loadStructure();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Area added')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error adding area: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                  child: const Text('Add Department'),
                ),
                const Divider(height: 20),
                const Text('Add New Area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                FutureBuilder<Map<String, dynamic>>(
                  future: _firestoreService.getFactoryStructure(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final data = snapshot.data!;
                    return Column(
                      children: [
                        const Text('Select Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: data.keys.map((dept) => ChoiceChip(
                            label: Text(dept),
                            selected: selectedDeptForArea == dept,
                            onSelected: (_) => setState(() => selectedDeptForArea = dept),
                            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                            labelStyle: selectedDeptForArea == dept ? TextStyle(color: Theme.of(context).colorScheme.onPrimary) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: areaController,
                          decoration: const InputDecoration(labelText: 'Area name'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedDeptForArea == null || areaController.text.isEmpty) return;
                            try {
                              final structure = await _firestoreService.getFactoryStructure();
                              (structure[selectedDeptForArea] as Map<String, dynamic>)[areaController.text] = [];
                              await _firestoreService.updateFactoryStructure(structure);
                              areaController.clear();
                              _loadStructure();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Area added')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error adding area: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: const Text('Add Area'),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 20),
                const Text('Add New Machine / Part', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                FutureBuilder<Map<String, dynamic>>(
                  future: _firestoreService.getFactoryStructure(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final data = snapshot.data!;
                    final areas = selectedDeptForMachine != null ? (data[selectedDeptForMachine] as Map<String, dynamic>? ?? {}).keys.toList() : <String>[];
                    return Column(
                      children: [
                        const Text('Select Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: data.keys.map((dept) => ChoiceChip(
                            label: Text(dept),
                            selected: selectedDeptForMachine == dept,
                            onSelected: (_) => setState(() {
                              selectedDeptForMachine = dept;
                              selectedAreaForMachine = null;
                            }),
                            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                            labelStyle: selectedDeptForMachine == dept ? TextStyle(color: Theme.of(context).colorScheme.onPrimary) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                          )).toList(),
                        ),
                        if (selectedDeptForMachine != null) ...[
                          const SizedBox(height: 8),
                          const Text('Select Area', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: areas.map((area) => ChoiceChip(
                              label: Text(area),
                              selected: selectedAreaForMachine == area,
                              onSelected: (_) => setState(() => selectedAreaForMachine = area),
                              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                              labelStyle: selectedAreaForMachine == area ? TextStyle(color: Theme.of(context).colorScheme.onPrimary) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                            )).toList(),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: machineController,
                          decoration: const InputDecoration(labelText: 'Machine / Part name'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedDeptForMachine == null || selectedAreaForMachine == null || machineController.text.isEmpty) return;
                            try {
                              final structure = await _firestoreService.getFactoryStructure();
                              (structure[selectedDeptForMachine]![selectedAreaForMachine] as List<dynamic>).add(machineController.text);
                              await _firestoreService.updateFactoryStructure(structure);
                              machineController.clear();
                              _loadStructure();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Machine added')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error adding machine: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: const Text('Add Machine / Part'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStructureList() {
    final query = structureSearchController.text.toLowerCase();
    final filteredStructure = <String, dynamic>{};
    _structure.forEach((dept, areas) {
      if (dept.toLowerCase().contains(query)) {
        filteredStructure[dept] = areas;
      } else {
        final filteredAreas = <String, dynamic>{};
        (areas as Map<String, dynamic>).forEach((area, machines) {
          if (area.toLowerCase().contains(query) || (machines as List).any((m) => m.toString().toLowerCase().contains(query))) {
            filteredAreas[area] = machines;
          }
        });
        if (filteredAreas.isNotEmpty) {
          filteredStructure[dept] = filteredAreas;
        }
      }
    });

    return filteredStructure.entries.map((deptEntry) {
      return ExpansionTile(
        title: Row(
          children: [
            Text(deptEntry.key),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteDepartment(deptEntry.key),
            ),
          ],
        ),
        children: (deptEntry.value as Map<String, dynamic>).entries.map((areaEntry) {
          return ExpansionTile(
            title: Row(
              children: [
                Text(areaEntry.key),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteArea(deptEntry.key, areaEntry.key),
                ),
              ],
            ),
            children: (areaEntry.value as List).map((machine) {
              return ListTile(
                title: Text(machine.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteMachine(deptEntry.key, areaEntry.key, machine.toString()),
                ),
              );
            }).toList(),
          );
        }).toList(),
      );
    }).toList();
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('App Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Switch User Password'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _updateSettings,
            child: const Text('Save Settings'),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Copper Storage'),
            onTap: () {
              if (_currentClockNo == '22') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CopperDashboardScreen()));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Access denied. Only clock card 22 allowed.')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.map, color: Color(0xFFFF8C42)),
            title: const Text('Edit Geofence Location'),
            subtitle: const Text('Change site location and radius on map'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GeofenceEditorScreen()),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await LocationService().checkCurrentLocation();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Location check completed'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.location_on),
            label: const Text('Force Location Check Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C42),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                // This simulates what the 30-minute WorkManager task does
                await LocationService().checkCurrentLocation();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Simulated 30-min WorkManager check completed'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.timer),
            label: const Text('Simulate 30-min WorkManager Check'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          _buildEscalationConfigSection(),
        ],
      ),
    );
  }

  Widget _buildEscalationConfigSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escalation Rules',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Controls when unassigned jobs escalate and who gets notified at each stage.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 24),

            // Timing
            const Text('Escalation Timing (minutes)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _shortMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stage 1',
                      helperText: 'e.g. 2 min',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _longMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stage 2',
                      helperText: 'e.g. 7 min',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _offsiteMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stage 3',
                      helperText: 'e.g. 30 min',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _stage4MinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stage 4',
                      helperText: 'e.g. 60 min',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _buildStageRecipients(
              label: 'Stage 1 Recipients',
              subtitle: 'Notified when job has had no action',
              selected: _stage1Recipients,
              onChanged: (rule, checked) => setState(() {
                checked ? _stage1Recipients.add(rule) : _stage1Recipients.remove(rule);
              }),
            ),

            const SizedBox(height: 16),
            _buildStageRecipients(
              label: 'Stage 2 Recipients',
              subtitle: 'Notified when job still unassigned after Stage 1',
              selected: _stage2Recipients,
              onChanged: (rule, checked) => setState(() {
                checked ? _stage2Recipients.add(rule) : _stage2Recipients.remove(rule);
              }),
            ),

            const SizedBox(height: 16),
            _buildStageRecipients(
              label: 'Stage 3 Recipients',
              subtitle: 'Reserved for future use (e.g. off-site managers)',
              selected: _stage3Recipients,
              onChanged: (rule, checked) => setState(() {
                checked ? _stage3Recipients.add(rule) : _stage3Recipients.remove(rule);
              }),
            ),

            const SizedBox(height: 16),
            _buildStageRecipients(
              label: 'Stage 4 Recipients',
              subtitle: 'Final escalation stage',
              selected: _stage4Recipients,
              onChanged: (rule, checked) => setState(() {
                checked ? _stage4Recipients.add(rule) : _stage4Recipients.remove(rule);
              }),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveNotificationConfig,
                icon: const Icon(Icons.save),
                label: const Text('Save Escalation Config'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C42),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageRecipients({
    required String label,
    required String subtitle,
    required Set<String> selected,
    required void Function(String rule, bool checked) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 0,
          runSpacing: 0,
          children: _allRules.map((rule) {
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(_ruleLabels[rule] ?? rule, style: const TextStyle(fontSize: 13)),
              value: selected.contains(rule),
              onChanged: (v) => onChanged(rule, v ?? false),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showEmployeeDialog([Employee? employee]) {
    final isEdit = employee != null;
    final clockNoController = TextEditingController(text: employee?.clockNo ?? '');
    final nameController = TextEditingController(text: employee?.name ?? '');
    final positionController = TextEditingController(text: employee?.position ?? '');
    final departmentController = TextEditingController(text: employee?.department ?? '');
    final fcmTokenController = TextEditingController(text: employee?.fcmToken ?? '');
    bool isOnSite = employee?.isOnSite ?? true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Employee' : 'Add Employee'),
        content: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: clockNoController,
                  decoration: const InputDecoration(labelText: 'Clock No *'),
                  enabled: !isEdit,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(labelText: 'Position *'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: departmentController,
                  decoration: const InputDecoration(labelText: 'Department *'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: fcmTokenController,
                  decoration: const InputDecoration(labelText: 'FCM Token'),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('On Site'),
                  value: isOnSite,
                  onChanged: (value) => setState(() => isOnSite = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (clockNoController.text.isEmpty || nameController.text.isEmpty || positionController.text.isEmpty || departmentController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Required fields missing'), backgroundColor: Colors.red),
                );
                return;
              }
              try {
                final emp = Employee(
                  clockNo: clockNoController.text,
                  name: nameController.text,
                  position: positionController.text,
                  department: departmentController.text,
                  fcmToken: fcmTokenController.text.isEmpty ? null : fcmTokenController.text,
                  isOnSite: isOnSite,
                  fcmTokenUpdatedAt: employee?.fcmTokenUpdatedAt,
                );
                if (isEdit) {
                  await _firestoreService.updateEmployee(emp);
                } else {
                  await _firestoreService.createEmployee(emp);
                }
                Navigator.pop(context);
                _loadEmployees();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Employee ${isEdit ? 'updated' : 'added'}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _deleteEmployee(String clockNo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _firestoreService.deleteEmployee(clockNo);
        _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteDepartment(String dept) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Department'),
        content: const Text('This will delete all areas and machines in this department. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        _structure.remove(dept);
        await _firestoreService.updateFactoryStructure(_structure);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Department deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteArea(String dept, String area) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Area'),
        content: const Text('This will delete all machines in this area. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        (_structure[dept] as Map).remove(area);
        await _firestoreService.updateFactoryStructure(_structure);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Area deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteMachine(String dept, String area, String machine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Machine'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final machines = _structure[dept][area] as List;
        machines.remove(machine);
        await _firestoreService.updateFactoryStructure(_structure);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Machine deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _updateSettings() async {
    try {
      await _firestoreService.updateSwitchUserPassword(_passwordController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _parseBool(String value) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'yes' || lower == 'on';
  }

  // ==================== EXPORT TEMPLATE ====================
  void _exportTemplate() {
    final csvData = [
      ['clockNo', 'name', 'position', 'department', 'isOnSite', 'fcmToken'],
      ['', '', '', '', 'true', ''],
    ];

    final csvString = const ListToCsvConverter().convert(csvData);

    if (kIsWeb) {
      final blob = html.Blob([csvString], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = 'employees_template.csv'
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      Share.share(csvString, subject: 'Employees Template');
    }
  }

  // ==================== IMPORT CSV ====================
  void _importCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String csvString;

      if (file.bytes != null) {
        csvString = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        csvString = await File(file.path!).readAsString();
      } else {
        return;
      }

      final csvTable = const CsvToListConverter().convert(csvString);

      if (csvTable.isEmpty || csvTable[0].length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid CSV format')),
        );
        return;
      }

      final headers = csvTable[0].map((e) => e.toString().trim().toLowerCase()).toList();
      final expected = ['clockno', 'name', 'position', 'department', 'isonsite', 'fcmtoken'];

      if (!expected.every((h) => headers.contains(h))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid headers in CSV')),
        );
        return;
      }

      final rows = csvTable.skip(1).map((row) => {
        'clockNo': row[headers.indexOf('clockno')].toString().trim(),
        'name': row[headers.indexOf('name')].toString().trim(),
        'position': row[headers.indexOf('position')].toString().trim(),
        'department': row[headers.indexOf('department')].toString().trim(),
        'isOnSite': _parseBool(row[headers.indexOf('isonsite')].toString().trim()),
        'fcmToken': row[headers.indexOf('fcmtoken')].toString().trim().isEmpty
            ? null
            : row[headers.indexOf('fcmtoken')].toString().trim(),
      }).toList();

      bool deleteAll = false;

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Preview Import'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  CheckboxListTile(
                    title: const Text('Delete all existing employees first'),
                    value: deleteAll,
                    onChanged: (v) => setState(() => deleteAll = v ?? false),
                  ),
                  Expanded(
                    child: ListView(
                      children: rows
                          .map((row) => ListTile(
                                title: Text('${row['clockNo']} - ${row['name']}'),
                                subtitle: Text('${row['position']} - ${row['department']}'),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if (deleteAll) {
                    await _firestoreService.deleteAllEmployees();
                  }

                  int imported = 0;
                  int skipped = 0;

                  for (final row in rows) {
                    if (row['clockNo'].toString().isEmpty) {
                      skipped++;
                      continue;
                    }

                    final emp = Employee(
                      clockNo: row['clockNo'] as String,
                      name: row['name'] as String,
                      position: row['position'] as String,
                      department: row['department'] as String,
                      isOnSite: row['isOnSite'] as bool,
                      fcmToken: row['fcmToken'] as String?,
                    );

                    try {
                      await _firestoreService.updateEmployee(emp);
                      imported++;
                    } catch (e) {
                      skipped++;
                    }
                  }

                  _loadEmployees();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Imported $imported, skipped $skipped')),
                  );
                },
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  void _toggleEdit(int index) {
    if (_editingIndex == index) {
      // save
      final emp = _allEmployees[index];
      final updatedEmp = emp.copyWith(
        clockNo: _clockNoController.text,
        name: _nameController.text,
        position: _positionController.text,
        department: _departmentController.text,
        fcmToken: _fcmController.text.isEmpty ? null : _fcmController.text,
      );
      _firestoreService.updateEmployee(updatedEmp);
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
    final toDelete = _selectedRows.map((i) => _allEmployees[i].clockNo).toList();
    for (final clockNo in toDelete) {
      await _firestoreService.deleteEmployee(clockNo);
    }
    _selectedRows.clear();
    setState(() {});
  }

  void _toggleJobCardEdit(int index) {
    if (_editingJobCardIndex == index) {
      // save
      final jc = _filteredJobCards[index];
      final updatedJc = jc.copyWith(
        priority: int.tryParse(_jobCardPriorityController.text) ?? jc.priority,
        status: JobStatusExtension.fromString(_jobCardStatusController.text) ?? jc.status,
        description: _jobCardDescriptionController.text,
      );
      _firestoreService.updateJobCard(jc.id!, updatedJc);
      _editingJobCardIndex = null;
    } else {
      _editingJobCardIndex = index;
      final jc = _filteredJobCards[index];
      _jobCardPriorityController.text = jc.priority.toString();
      _jobCardStatusController.text = jc.status.name;
      _jobCardDescriptionController.text = jc.description;
    }
    setState(() {});
  }

  void _deleteJobCard(JobCard jc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Job Card'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _firestoreService.deleteJobCard(jc.id!);
        _loadJobCards();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Job card deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _bulkDeleteJobCards() async {
    final toDelete = _selectedJobCardRows.map((i) => _filteredJobCards[i]).toList();
    for (final jc in toDelete) {
      await _firestoreService.deleteJobCard(jc.id!);
    }
    _selectedJobCardRows.clear();
    setState(() {});
  }

  void _exportJobCardsCsv() {
    final csvData = [
      ['Job #', 'Priority', 'Status', 'Type', 'Department', 'Area', 'Machine', 'Part', 'Description', 'Operator', 'Assigned Count', 'Created At'],
      ..._allJobCards.map((jc) => [
        jc.jobCardNumber?.toString() ?? '',
        jc.priority.toString(),
        jc.status.displayName,
        jc.type.displayName,
        jc.department,
        jc.area,
        jc.machine,
        jc.part,
        jc.description,
        jc.operator,
        jc.assignedClockNos?.length.toString() ?? '0',
        jc.createdAt?.toString() ?? '',
      ]),
    ];
    final csvString = const ListToCsvConverter().convert(csvData);
    if (kIsWeb) {
      final blob = html.Blob([csvString], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)..download = 'job_cards.csv'..click();
      html.Url.revokeObjectUrl(url);
    } else {
      Share.share(csvString, subject: 'Job Cards Export');
    }
  }

  Widget _buildJobCardsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jobCardSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search Job Cards',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() => _filterJobCards()),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _selectedOperator,
                hint: const Text('Filter by Operator'),
                items: _allJobCards.map((jc) => jc.operator).toSet().map((op) => DropdownMenuItem(value: op, child: Text(op))).toList(),
                onChanged: (v) => setState(() {
                  _selectedOperator = v;
                  _filterJobCards();
                }),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _exportJobCardsCsv,
                icon: const Icon(Icons.download),
                label: const Text('Export All'),
              ),
              if (_selectedJobCardRows.isNotEmpty) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _bulkDeleteJobCards,
                  icon: const Icon(Icons.delete, color: Colors.white),
                  label: const Text('Delete Selected'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<JobCard>>(
            stream: _firestoreService.getAllJobCards(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && _allJobCards.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final jobCards = snapshot.data ?? _allJobCards;
              _allJobCards = jobCards;
              _filterJobCards();

              return PaginatedDataTable(
                header: const Text('Job Cards'),
                rowsPerPage: 10,
                columns: const [
                  DataColumn(label: Text('Select')),
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
                  jobCards: _filteredJobCards,
                  selectedRows: _selectedJobCardRows,
                  editingIndex: _editingJobCardIndex,
                  onSelectChanged: (index) {
                    if (_selectedJobCardRows.contains(index)) {
                      _selectedJobCardRows.remove(index);
                    } else {
                      _selectedJobCardRows.add(index);
                    }
                    setState(() {});
                  },
                  onEditToggle: _toggleJobCardEdit,
                  onDelete: _deleteJobCard,
                  priorityController: _jobCardPriorityController,
                  statusController: _jobCardStatusController,
                  descriptionController: _jobCardDescriptionController,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}



